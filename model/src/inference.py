import os
import torch
import torch.nn as nn
import torch.nn.functional as F
import numpy as np

from cnn import CNN
from data_loader import normalize_features, interpolate_to_fixed_length

class MovementQualityInference:
    def __init__(self, movement_name, model_weights_path):
        """
        Initializes the correct model architecture based on the movement name
        and loads the specific trained weights.
        """
        self.device = torch.device("cpu") # Keep on CPU for mobile/Zetic prep
        self.movement_name = movement_name
        
        # Categorize the movement to select the architecture
        ROM_MOVEMENTS = ["ElbFlex", "ShFlex90", "ShHorAdd", "FrontSupPro"]
        ADL_MOVEMENTS = ["TakePill", "PourWater", "BrushTeeth"]
        
        ALL_VALID = ROM_MOVEMENTS + ADL_MOVEMENTS + ["Unified"]
        if self.movement_name in ALL_VALID:
            self.model = CNN()
            print(f"[{movement_name}] Loaded CNN Architecture.")
        else:
            print(f"ERROR, MOVEMENT NAME NOT IN MOVEMENTS, WAS: {self.movement_name}")
            
        # Load weights and set to EVALUATION mode
        try:
            self.model.load_state_dict(torch.load(model_weights_path, map_location=self.device, weights_only=True))
            print(f"Successfully loaded weights from: {model_weights_path}")
        except FileNotFoundError:
            print(f"Warning: No weights found at {model_weights_path}. Exiting.")
            raise RuntimeError
            
        self.model.to(self.device)
        self.model.eval() # CRITICAL: Disables Dropout for live inference

        # Load GLOBAL normalization stats next to the weights file (e.g. ElbFlex_stats.npz).
        # Falls back to legacy per-sample Z-score if the stats file is missing
        # (so older models still load).
        self.global_mean = None
        self.global_std = None
        stats_path = model_weights_path.replace("_weights.pt", "_stats.npz")
        if os.path.exists(stats_path):
            stats = np.load(stats_path)
            self.global_mean = stats["mean"].astype(np.float32)
            self.global_std = stats["std"].astype(np.float32)
            print(f"Loaded global normalization stats from: {stats_path}")
        else:
            print(f"WARNING: No stats file at {stats_path}; falling back to per-sample Z-score "
                  "(may not match training preprocessing).")

    def preprocess_live_buffer(self, raw_sensor_data):
        """
        Takes a raw 2D numpy array of incoming live sensor data (variable length, 12 channels)
        and applies the SAME preprocessing as training: Z-score normalization + interpolation.
        Returns tensor of shape (1, INTERPOLATION_SIZE, 12).
        """
        # Convert raw numpy array to PyTorch tensor
        # Expected input shape: (variable_length, 12)
        tensor_features = torch.tensor(raw_sensor_data, dtype=torch.float32)
        
        # CRITICAL: Apply the same normalization used during training
        # (global per-channel if stats were loaded; else per-sample Z-score fallback)
        tensor_features = normalize_features(
            tensor_features, self.global_mean, self.global_std
        )
        
        # Interpolate to fixed temporal resolution (matches training)
        tensor_features = interpolate_to_fixed_length(tensor_features)
        
        # Add batch dimension: (INTERPOLATION_SIZE, 12) -> (1, INTERPOLATION_SIZE, 12)
        return tensor_features.unsqueeze(0)

    def get_live_score(self, raw_sensor_data):
        """
        Executes the full pipeline: preprocesses live data, runs inference without gradients,
        and returns the gamified 0-100 score.
        """
        
        # 1. Format the data
        model_input = self.preprocess_live_buffer(raw_sensor_data)
        
        # 2. Run inference (Disable gradient tracking for speed/memory)
        with torch.no_grad():
            prediction = self.model(model_input)
            
            # Apply softmax to convert raw logits into 0.0 - 1.0 probabilities
            probabilities = F.softmax(prediction, dim=1)
            
            # prediction shape is (1, 2) -> [[Prob_Stroke, Prob_Healthy]]
            # We want the probability of Class 1 (Healthy)
            healthy_probability = probabilities[0][1].item()
            
        # 3. Gamify the score (0 to 100)
        live_score = int(healthy_probability * 100)
        return live_score