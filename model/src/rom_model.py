import torch
import torch.nn as nn

class ROM_CNN(nn.Module):
    def __init__(self):
        super(ROM_CNN, self).__init__()
        
        # PyTorch Conv1d expects shape: (Batch, Channels, Length)
        # We will transpose the (Batch, 20, 12) input to (Batch, 12, 20) in the forward pass.
        
        # Convolutional Layers (Padding=2 keeps the dimensions mathematically viable)
        # Layer 1: Length drops 20 -> 10
        self.conv1 = nn.Conv1d(in_channels=12, out_channels=32, kernel_size=5, stride=2, padding=2)
        # Layer 2: Length drops 10 -> 5
        self.conv2 = nn.Conv1d(in_channels=32, out_channels=64, kernel_size=5, stride=2, padding=2)
        # Layer 3: Length drops 5 -> 3
        self.conv3 = nn.Conv1d(in_channels=64, out_channels=128, kernel_size=5, stride=2, padding=2)
        # Layer 4: Length drops 3 -> 2
        self.conv4 = nn.Conv1d(in_channels=128, out_channels=256, kernel_size=5, stride=2, padding=2)
        
        self.relu = nn.ReLU()
        self.flatten = nn.Flatten()
        
        # Classification Head
        # Flattened size: 256 channels * 2 temporal length = 512
        self.fc1 = nn.Linear(in_features=512, out_features=200) 
        self.dropout = nn.Dropout(p=0.7)
        
        # Output: 2 classes (0 = Stroke, 1 = Healthy)
        self.fc2 = nn.Linear(in_features=200, out_features=2)
        self.softmax = nn.Softmax(dim=1)

    def forward(self, x):
        # 1. Transpose: (Batch, 20 windows, 12 channels) -> (Batch, 12 channels, 20 windows)
        x = x.transpose(1, 2)
        
        # 2. Feature Extraction
        x = self.relu(self.conv1(x))
        x = self.relu(self.conv2(x))
        x = self.relu(self.conv3(x))
        x = self.relu(self.conv4(x))
        
        # 3. Flatten for Dense Layers
        x = self.flatten(x)
        
        # 4. Classification
        x = self.relu(self.fc1(x))
        x = self.dropout(x)
        x = self.fc2(x)
        
        # 5. Probability Conversion
        # x = self.softmax(x)
        return x
    
__all__ = ["ROM_CNN", ]