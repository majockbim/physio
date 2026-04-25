import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
from torch.utils.data import DataLoader
import pandas as pd
import numpy as np
import os

from adl_model import ADL_CNN
from data_loader import JUIMUDataset
from rom_model import ROM_CNN

class MovementTrainer:
    def __init__(self, movement_name, model_type="ROM", lr=0.001, weight_decay=0.01, *, debug=False):
        """
        Initializes the trainer for a specific movement.
        model_type: "ROM" or "ADL"
        """
        self.movement_name = movement_name
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self.debug = debug
        print(f"[{self.movement_name}] Training on device: {self.device}")
        
        # Select Architecture
        if model_type == "ROM":
            self.model = ROM_CNN(debug=self.debug).to(self.device)
        else:
            self.model = ADL_CNN(debug=self.debug).to(self.device)
            
        # Optimizer & Loss (AdamW as specified in your plan)
        self.optimizer = optim.AdamW(self.model.parameters(), lr=lr, weight_decay=weight_decay)
        self.criterion = nn.CrossEntropyLoss()

    def train(self, train_files, patient_info_path, train_labels, epochs=40, batch_size=256):
        """
        Executes the training loop over the provided dataset.
        """
        # Load Dataset
        dataset = JUIMUDataset(train_files, patient_info_path, train_labels)
        dataloader = DataLoader(dataset, batch_size=batch_size, shuffle=True)
        
        self.model.train() # Turn ON Dropout and gradients
        
        print(f"[{self.movement_name}] Starting training for {epochs} epochs...")
        for epoch in range(epochs):
            running_loss = 0.0
            correct_predictions = 0
            total_samples = 0
            
            for features, labels in dataloader:
                # Move data to GPU if available
                features, labels = features.to(self.device), labels.to(self.device)
                
                # Zero gradients
                self.optimizer.zero_grad()
                
                # Forward pass
                outputs = self.model(features)
                # if self.debug:
                #     print(f"DEBUG: Label shape for training: {labels.shape}")
                loss = self.criterion(outputs, labels)
                
                # Backward pass & optimize
                loss.backward()
                self.optimizer.step()
                
                # Track metrics
                running_loss += loss.item()
                _, predicted = torch.max(outputs.data, 1) # Get the index of the highest logit
                total_samples += labels.size(0)
                correct_predictions += (predicted == labels).sum().item()
                
            # Print epoch summary
            epoch_loss = running_loss / len(dataloader)
            epoch_acc = (correct_predictions / total_samples) * 100
            if (epoch + 1) % 5 == 0 or epoch == 0:
                print(f"Epoch [{epoch+1}/{epochs}] - Loss: {epoch_loss:.4f} - Accuracy: {epoch_acc:.2f}%")
                
        print(f"[{self.movement_name}] Training complete!")

    def save_model(self, save_dir="models"):
        """
        Saves the trained model weights to a .pt file.
        """
        if not os.path.exists(save_dir):
            os.makedirs(save_dir)
            
        save_path = os.path.join(save_dir, f"{self.movement_name}_weights.pt")
        torch.save(self.model.state_dict(), save_path)
        print(f"[{self.movement_name}] Weights successfully saved to {save_path}")
    
__all__ = ["MovementTrainer", ]