import torch
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader
import pandas as pd
import numpy as np

from cnn import INTERPOLATION_SIZE

def normalize_features(tensor_features):
    """Apply per-sample Z-score normalization across the time dimension."""
    mean = tensor_features.mean(dim=0, keepdim=True)
    std = tensor_features.std(dim=0, keepdim=True) + 1e-7
    return (tensor_features - mean) / std

def interpolate_to_fixed_length(tensor_features, size=INTERPOLATION_SIZE):
    """Interpolate (variable_length, 12) tensor to (size, 12)."""
    # F.interpolate expects (batch, channels, length)
    x = tensor_features.transpose(0, 1).unsqueeze(0)
    x = F.interpolate(x, size=size, mode='linear', align_corners=False)
    return x.squeeze(0).transpose(0, 1)

def augment_axis_rotation(features):
    """
    Apply random 3D rotation to accelerometer and gyroscope vector groups.
    Simulates natural variability in sensor orientation (per paper methodology).
    Channels layout: [acc_x, acc_y, acc_z, gyro_x, gyro_y, gyro_z] x 2 sensors
    """
    # Random rotation angle in [-90°, +90°]
    angle = (torch.rand(1) * np.pi) - (np.pi / 2)
    # Random rotation axis (unit vector)
    axis = torch.randn(3)
    axis = axis / (axis.norm() + 1e-7)
    
    # Rodrigues' rotation formula: R = I + sin(a)*K + (1-cos(a))*K^2
    K = torch.tensor([
        [0, -axis[2], axis[1]],
        [axis[2], 0, -axis[0]],
        [-axis[1], axis[0], 0]
    ])
    R = torch.eye(3) + torch.sin(angle) * K + (1 - torch.cos(angle)) * (K @ K)
    
    # Apply rotation to each 3D vector group (4 groups: acc1, gyro1, acc2, gyro2)
    features = features.clone()
    for start_idx in [0, 3, 6, 9]:
        vec = features[:, start_idx:start_idx + 3]  # (seq_len, 3)
        features[:, start_idx:start_idx + 3] = vec @ R.T
    return features

def augment_magnitude_scaling(features, low=0.8, high=1.2):
    """Scale all channels by a random factor — simulates sensor gain variability."""
    scale = torch.empty(1).uniform_(low, high)
    return features * scale

def augment_time_warp(features, sigma=0.2):
    """Slightly warp the time axis by interpolating through randomly displaced anchors."""
    seq_len = features.shape[0]
    if seq_len < 4:
        return features
    # Create random time warp by displacing a few anchor points
    n_anchors = 4
    orig = torch.linspace(0, 1, n_anchors)
    warp = orig + torch.randn(n_anchors) * sigma / n_anchors
    warp[0], warp[-1] = 0.0, 1.0  # keep endpoints fixed
    warp, _ = warp.sort()
    # Map original indices through warped anchors
    orig_idx = torch.linspace(0, 1, seq_len)
    warped_idx = torch.from_numpy(
        np.interp(orig_idx.numpy(), warp.numpy(), orig.numpy())
    ).float()
    # Convert to sample indices and interpolate
    sample_idx = warped_idx * (seq_len - 1)
    idx_floor = sample_idx.long().clamp(0, seq_len - 2)
    frac = (sample_idx - idx_floor.float()).unsqueeze(1)
    return features[idx_floor] * (1 - frac) + features[idx_floor + 1] * frac


class JUIMUDataset(Dataset):
    def __init__(self, file_paths, patient_info_path, labels, *, training=False, debug=False):
        """
        file_paths: List of string paths to the individual CSV files.
        patient_info_path: String path OR list of string paths (one per file) to the patient info file(s).
        labels: List of integers (1 for ND/Healthy, 0 for Stroke/Affected).
        """
        self.file_paths = file_paths
        # Support both single path and per-file paths for unified training
        if isinstance(patient_info_path, str):
            self.patient_info_paths = [patient_info_path] * len(file_paths)
        else:
            self.patient_info_paths = patient_info_path
        self.labels = labels
        self.training = training
        self.debug = debug

    def __len__(self):
        return len(self.file_paths)
    
    def get_patient_data(self, df, patient_file_path, patient_info_path=None):
        """
        Returns the sensor data corresponding to the given patient_file_path
        """
        
        if patient_info_path is None:
            patient_info_path = self.patient_info_paths[0]
        patient_info_df = pd.read_csv(patient_info_path)
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
        patient_info_path = self.patient_info_paths[idx]
        df = pd.read_csv(patient_file_path)
            
        selected_cols = self.get_patient_data(df, patient_file_path, patient_info_path)
        
        if self.debug:
            print(f'First data values are: {df[selected_cols].head()}')
        
        # Extract raw values -> Shape: (variable_length, 12)
        raw_features = df[selected_cols].values 
        
        # 3. Convert to PyTorch Tensor
        tensor_features = torch.tensor(raw_features, dtype=torch.float32)
        
        # 4. Apply Z-score normalization
        # This is because the scales of the accelerometers vs. gyroscopes are quite different
        tensor_features = normalize_features(tensor_features)
        
        # 5. Apply Data Augmentation (training only, before interpolation for max diversity)
        if self.training:
            tensor_features = augment_axis_rotation(tensor_features)
            tensor_features = augment_magnitude_scaling(tensor_features)
            # Gaussian jitter
            tensor_features = tensor_features + torch.randn_like(tensor_features) * 0.03
        
        # 6. Apply Linear Interpolation to fixed temporal resolution
        final_features = interpolate_to_fixed_length(tensor_features, size=INTERPOLATION_SIZE)
        
        # 7. Format Label
        label = torch.tensor(self.labels[idx], dtype=torch.long)
        
        return final_features, label
      
__all__ = ["JUIMUDataset", "normalize_features", "interpolate_to_fixed_length"]