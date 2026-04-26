import os
os.environ["CUDA_VISIBLE_DEVICES"] = ""  # Must be set before importing torch

import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
from torch.utils.data import DataLoader
import pandas as pd
import numpy as np

from cnn import CNN, INTERPOLATION_SIZE
from data_loader import JUIMUDataset, compute_global_stats

def mixup_data(x, y, alpha=0.4):
    """Mixup: blend pairs of training examples for better generalization on small datasets."""
    if alpha > 0:
        lam = np.random.beta(alpha, alpha)
    else:
        lam = 1.0
    batch_size = x.size(0)
    index = torch.randperm(batch_size, device=x.device)
    mixed_x = lam * x + (1 - lam) * x[index]
    y_a, y_b = y, y[index]
    return mixed_x, y_a, y_b, lam

def mixup_criterion(criterion, pred, y_a, y_b, lam):
    """Compute loss for mixup-blended targets."""
    return lam * criterion(pred, y_a) + (1 - lam) * criterion(pred, y_b)

class MovementTrainer:
    def __init__(self, movement_name, model_type="ROM", lr=0.001, weight_decay=0.05, *, debug=False):
        """
        Initializes the trainer for a specific movement.
        model_type: "ROM" or "ADL"
        """
        self.movement_name = movement_name
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self.debug = debug
        self.criterion = None  # Will be initialized in train() with actual class weights
        print(f"[{self.movement_name}] Training on device: {self.device}")
        
        # Select Architecture
        if model_type == "ROM":
            self.model = CNN(debug=self.debug).to(self.device)
        else:
            self.model = CNN(debug=self.debug).to(self.device)
        
        # Optimizer (will use default learning rate)
        self.optimizer = optim.AdamW(self.model.parameters(), lr=lr, weight_decay=weight_decay)

        # Global normalization stats (filled in during train())
        self.global_mean = None
        self.global_std = None

    def train(self, train_files, patient_info_path, train_labels, epochs=60, batch_size=16):
        """
        Executes the training loop over the provided dataset.
        patient_info_path: Single string or list of strings (one per file).
        """
        # Compute GLOBAL per-channel mean/std across the training set ONCE.
        # This preserves cross-patient magnitude differences (key for stroke
        # detection) instead of erasing them with per-sample Z-score.
        print(f"[{self.movement_name}] Computing global per-channel normalization stats...")
        self.global_mean, self.global_std = compute_global_stats(train_files, patient_info_path)
        print(f"[{self.movement_name}]   mean[:6]={self.global_mean[:6].round(2)}, "
              f"std[:6]={self.global_std[:6].round(2)}")

        # Load Dataset (now uses global stats instead of per-sample Z-score)
        dataset = JUIMUDataset(
            train_files, patient_info_path, train_labels,
            training=True,
            global_mean=self.global_mean, global_std=self.global_std,
        )
        dataloader = DataLoader(dataset, batch_size=batch_size, shuffle=True)
        
        # Compute class weights dynamically from actual training data distribution
        label_counts = np.bincount(train_labels)
        class_weights = 1.0 / (label_counts / label_counts.sum())
        class_weights = class_weights / class_weights.sum() * 2  # Normalize so average is ~1
        class_weights = torch.tensor(class_weights, dtype=torch.float32).to(self.device)
        self.criterion = nn.CrossEntropyLoss(weight=class_weights, label_smoothing=0.1)
        
        # Learning rate scheduler: cosine annealing for smooth convergence
        scheduler = optim.lr_scheduler.CosineAnnealingLR(self.optimizer, T_max=epochs, eta_min=1e-5)
        
        if self.debug:
            print(f"Class distribution: {label_counts}")
            print(f"Class weights: {class_weights}")
        
        self.model.train() # Turn ON Dropout and gradients
        
        print(f"[{self.movement_name}] Starting training for {epochs} epochs...")
        for epoch in range(epochs):
            running_loss = 0.0
            correct_predictions = 0
            total_samples = 0
            
            for features, labels in dataloader:
                # Move data to GPU if available
                features, labels = features.to(self.device), labels.to(self.device)
                
                # Apply mixup augmentation (blends pairs of samples for better generalization)
                mixed_features, labels_a, labels_b, lam = mixup_data(features, labels, alpha=0.4)
                
                # Zero gradients
                self.optimizer.zero_grad()
                
                # Forward pass
                outputs = self.model(mixed_features)
                loss = mixup_criterion(self.criterion, outputs, labels_a, labels_b, lam)
                
                # Backward pass & optimize
                loss.backward()
                self.optimizer.step()
                
                # Track metrics (use original labels for accuracy tracking)
                running_loss += loss.item()
                _, predicted = torch.max(outputs.data, 1) # Get the index of the highest logit
                total_samples += labels.size(0)
                correct_predictions += (lam * (predicted == labels_a).sum().float() + 
                                       (1 - lam) * (predicted == labels_b).sum().float()).item()
            
            scheduler.step()
            
            # Print epoch summary
            epoch_loss = running_loss / len(dataloader)
            epoch_acc = (correct_predictions / total_samples) * 100
            if (epoch + 1) % 10 == 0 or epoch == 0:
                lr = scheduler.get_last_lr()[0]
                print(f"Epoch [{epoch+1}/{epochs}] - Loss: {epoch_loss:.4f} - Accuracy: {epoch_acc:.2f}% - LR: {lr:.6f}")
                
        print(f"[{self.movement_name}] Training complete!")

    def save_model(self, save_dir="models"):
        """
        Saves the trained model as a .pt2 file with dynamic batch size using torch.export.
        """
        
        # Get the device used for the model
        device = next(self.model.parameters()).device
        
        if not os.path.exists(save_dir):
            os.makedirs(save_dir)
            
        np_input_path = os.path.join(save_dir, "mobile", f"{self.movement_name}_input.npy")
        save_path = os.path.join(save_dir, f"{self.movement_name}_weights.pt")
        stats_path = os.path.join(save_dir, f"{self.movement_name}_stats.npz")
        mobile_save_path = os.path.join(save_dir, "mobile", f"{self.movement_name}_weights.pt2")
        
        # --------------------------------------------------
        # SAVE WEIGHTS FOR INFERENCE
        torch.save(self.model.state_dict(), save_path)

        # SAVE GLOBAL NORMALIZATION STATS so inference can apply identical preprocessing
        if self.global_mean is not None and self.global_std is not None:
            np.savez(stats_path, mean=self.global_mean, std=self.global_std)
            print(f"[{self.movement_name}] Saved normalization stats to {stats_path}")
        
        # --------------------------------------------------
        # EXPORT FOR MOBILE
        # Set model to eval mode for export
        model = self.model.cpu()
        model.eval()
        
        # Create example input with batch size 1: (batch, INTERPOLATION_SIZE, 12 channels)
        input_data = np.random.randn(1, INTERPOLATION_SIZE, 12).astype(np.float32)
        np.save(np_input_path, input_data)
        example_input = (torch.randn(1, INTERPOLATION_SIZE, 12).to(device),)
    
        ep = torch.export.export(
            model,
            args=example_input,
        )
        
        # Save the exported program
        torch.export.save(ep, mobile_save_path)
        print(f"[{self.movement_name}] Exported model successfully saved to {mobile_save_path}")
    
__all__ = ["MovementTrainer", ]