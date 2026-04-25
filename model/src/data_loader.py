import torch
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader
import pandas as pd
import numpy as np

class JUIMUDataset(Dataset):
    def __init__(self, file_paths, patient_info_path, labels, *, training=False, debug=False):
        """
        file_paths: List of string paths to the individual CSV files.
        patient_info_path: String path to the patient info file, containing which side is affected by stroke.
        labels: List of integers (1 for ND/Healthy, 0 for Stroke/Affected).
        """
        self.file_paths = file_paths
        self.patient_info_path = patient_info_path
        self.labels = labels
        self.training = training
        self.debug = debug

    def __len__(self):
        return len(self.file_paths)
    
    def get_patient_data(self, df, patient_file_path):
        """
        Returns the sensor data corresponding to the given patient_file_path
        """
        
        patient_info_df = pd.read_csv(self.patient_info_path)
        # Files have name format "[ROM/ADL]_[PATIENT_ID]_...", where PATIENT_ID is ND[#] or Stroke[#]
        patient_id = patient_file_path.split('_')[1]
        patient_info = patient_info_df.loc[(patient_info_df['id'] == patient_id).idxmax()]
        
        # 2. Extract the 12 Channels (Sensor 1 & Sensor 4)
        # The dataset has 5 sensors * 9 channels = 45 total columns.
        # We need cols 0-5 (Sensor 1) and cols 27-32 (Sensor 4).
        # Uses sensors 2 and 5 for left hemiparesis
        
        # If patient has left hemiparesis, exchange sensor data
        if patient_info['side'] == 'L':
            side = 'left'
            # Switch from column 2 to 1, 5 to 4
            wrist_columns = self._get_sensor_data(df, 2)   # acc_x, acc_y, acc_z, gyro_x, gyro_y, gyro_z
            bicep_columns = self._get_sensor_data(df, 5) # acc_x, acc_y, acc_z, gyro_x, gyro_y, gyro_z
        else:
            side = 'right'
            wrist_columns = self._get_sensor_data(df, 1)   # acc_x, acc_y, acc_z, gyro_x, gyro_y, gyro_z
            bicep_columns = self._get_sensor_data(df, 4) # acc_x, acc_y, acc_z, gyro_x, gyro_y, gyro_z
        
        if self.debug:
            print(f'Patient has {side} hemiparesis, with id {patient_id} and info {patient_info}')
            
        return list(wrist_columns) + list(bicep_columns)
            
    def _get_sensor_data(self, df, sensor_id: int):
        """
        df: Dataframe to get columns from.
        sensor_id: Int from 1 to 5 corresponding to sensor specified at https://github.com/youngminoh7/JU-IMU.
        """
        
        # Fix 1-indexing to 0-indexing
        sensor_id -= 1
        # We want the first 6 elements
        SENSOR_CHANNEL_COUNT = 6
        ORIGINAL_CHANNELS_PER_SENSOR = 9
        lower_index = sensor_id * ORIGINAL_CHANNELS_PER_SENSOR
        upper_index = lower_index + SENSOR_CHANNEL_COUNT
        return df.columns[lower_index:upper_index]

    def __getitem__(self, idx):
        # 1. Load the raw variable-length CSV
        patient_file_path = self.file_paths[idx]
        df = pd.read_csv(patient_file_path)
            
        selected_cols = self.get_patient_data(df, patient_file_path)
        
        if self.debug:
            print(f'First data values are: {df[selected_cols].head()}')
        
        # Extract raw values -> Shape: (variable_length, 12)
        raw_features = df[selected_cols].values 
        
        # 3. Convert to PyTorch Tensor
        tensor_features = torch.tensor(raw_features, dtype=torch.float32)
        
        # 4. Apply Z-score normalization
        # This is because the scales of the accelerometers vs. gyroscopes are quite different
        # mean = tensor_features.mean(dim=0, keepdim=True)
        # std = tensor_features.std(dim=0, keepdim=True) + 1e-7 # add epsilon to prevent div by zero
        # tensor_features = (tensor_features - mean) / std
        
        # 5. Apply Linear Interpolation
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
        
        # 6. Format Label
        label = torch.tensor(self.labels[idx], dtype=torch.long)
        
        if self.training:
            noise_factor = 0.01
            # noise_factor = 0.0
            noise = torch.randn_like(final_features) * noise_factor
            final_features = final_features + noise
        
        return final_features, label
      
__all__ = ["JUIMUDataset", ]