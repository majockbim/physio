import torch
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader
import pandas as pd
import numpy as np

class JUIMUDataset(Dataset):
    def __init__(self, file_paths, labels):
        """
        file_paths: List of string paths to the individual CSV files.
        labels: List of integers (1 for ND/Healthy, 0 for Stroke/Affected).
        """
        self.file_paths = file_paths
        self.labels = labels

    def __len__(self):
        return len(self.file_paths)

    def __getitem__(self, idx):
        # 1. Load the raw variable-length CSV
        df = pd.read_csv(self.file_paths[idx])
        
        # 2. Extract the 12 Channels (Sensor 1 & Sensor 4)
        # The dataset has 5 sensors * 9 channels = 45 total columns.
        # We need cols 0-5 (Sensor 1) and cols 27-32 (Sensor 4).
        # Adjust these specific column names/indices to match your exact CSV headers.
        sensor_1_cols = df.columns[0:6]   # acc_x, acc_y, acc_z, gyro_x, gyro_y, gyro_z
        sensor_4_cols = df.columns[27:33] # acc_x, acc_y, acc_z, gyro_x, gyro_y, gyro_z
        selected_cols = list(sensor_1_cols) + list(sensor_4_cols)
        
        # Extract raw values -> Shape: (variable_length, 12)
        raw_features = df[selected_cols].values 
        
        # 3. Convert to PyTorch Tensor
        tensor_features = torch.tensor(raw_features, dtype=torch.float32)
        
        # 4. Apply Linear Interpolation
        # PyTorch's F.interpolate expects 1D data to be shaped as: [batch_size, channels, sequence_length]
        # We must transpose our (length, 12) tensor to (12, length) and add a dummy batch dimension.
        tensor_features = tensor_features.transpose(0, 1).unsqueeze(0) # Shape: (1, 12, variable_length)
        
        # Interpolate down/up to exactly 20 windows
        interpolated = F.interpolate(
            tensor_features, 
            size=20, 
            mode='linear', 
            align_corners=False
        )
        
        # Reshape back to the plan's required output: (20, 12)
        final_features = interpolated.squeeze(0).transpose(0, 1)
        
        # 5. Format Label
        label = torch.tensor([self.labels[idx]], dtype=torch.float32)
        
        return final_features, label
      
__all__ = ["JUIMUDataset"]