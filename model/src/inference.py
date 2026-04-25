import torch
import torch.nn as nn
import torch.nn.functional as F
import numpy as np

from rom_model import ROM_CNN
from adl_model import ADL_CNN

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
        
        if self.movement_name in ROM_MOVEMENTS:
            self.model = ROM_CNN()
            print(f"[{movement_name}] Loaded ROM_CNN Architecture.")
        elif self.movement_name in ADL_MOVEMENTS:
            self.model = ADL_CNN()
            print(f"[{movement_name}] Loaded ADL_CNN Architecture.")
        else:
            print(f"ERROR, MOVEMENT NAME NOT IN MOVEMENTS, WAS: {self.movement_name}")
            
        # Load weights and set to EVALUATION mode
        try:
            self.model.load_state_dict(torch.load(model_weights_path, map_location=self.device))
            print(f"Successfully loaded weights from: {model_weights_path}")
        except FileNotFoundError:
            print(f"Warning: No weights found at {model_weights_path}. Exiting.")
            raise RuntimeError
            
        self.model.to(self.device)
        self.model.eval() # CRITICAL: Disables Dropout for live inference

    def preprocess_live_buffer(self, raw_sensor_data):
        """
        Takes a raw 2D numpy array of incoming live sensor data (variable length, 12 channels)
        and interpolates it down to the exact (1, 20, 12) tensor required by the model.
        """
        
        print(raw_sensor_data)
        # Convert raw numpy array to PyTorch tensor
        # Expected input shape: (variable_length, 12)
        tensor_features = torch.tensor(raw_sensor_data, dtype=torch.float32)
        
        # Transpose and add dummy batch dimension for interpolation
        # Shape becomes: (1, 12, variable_length)
        tensor_features = tensor_features.transpose(0, 1).unsqueeze(0) 
        
        # Apply Linear Interpolation down to 20 windows
        interpolated = F.interpolate(
            tensor_features, 
            size=20, 
            mode='linear', 
            align_corners=False
        )
        
        # Reshape to (Batch=1, Windows=20, Channels=12)
        final_features = interpolated.squeeze(0).transpose(0, 1).unsqueeze(0)
        return final_features

    def get_live_score(self, raw_sensor_data):
        """
        Executes the full pipeline: preprocesses live data, runs inference without gradients,
        and returns the gamified 0-100 score.
        """
        
        # print(f"Raw sensor data shape: {raw_sensor_data.shape}")
        
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