import torch
import torch.nn as nn

# Shared constant: temporal resolution after interpolation
INTERPOLATION_SIZE = 128

class CNN(nn.Module):
    def __init__(self, n_channels=12, *, debug=False):
        super(CNN, self).__init__()
        
        # PyTorch Conv1d expects shape: (Batch, Channels, Length)
        # We will transpose the (Batch, INTERPOLATION_SIZE, 12) input in the forward pass.
        
        # 3 Conv blocks with BatchNorm for stability on small datasets
        # ~38K params total (vs ~320K before) — better suited for ~35 training samples
        self.features = nn.Sequential(
            # Layer 1: 128 -> 64
            nn.Conv1d(n_channels, 32, kernel_size=7, stride=2, padding=3),
            nn.GroupNorm(8, 32),
            nn.ReLU(),
            
            # Layer 2: 64 -> 32
            nn.Conv1d(32, 64, kernel_size=5, stride=2, padding=2),
            nn.GroupNorm(8, 64),
            nn.ReLU(),
            
            # Layer 3: 32 -> 16
            nn.Conv1d(64, 128, kernel_size=3, stride=2, padding=1),
            nn.GroupNorm(8, 128),
            nn.ReLU(),
        )
        
        # Global average pooling removes need for large FC layer & makes model input-length flexible
        self.pool = nn.AdaptiveAvgPool1d(1)
        self.dropout = nn.Dropout(p=0.5)
        
        # Output: 2 classes (0 = Stroke, 1 = Healthy)
        self.fc = nn.Linear(128, 2)

    def forward(self, x):
        # 1. Transpose: (Batch, SeqLen, Channels) -> (Batch, Channels, SeqLen)
        x = x.transpose(1, 2)
        
        # 2. Feature Extraction (Conv + BN + ReLU)
        x = self.features(x)
        
        # 3. Global Average Pooling -> (Batch, 128)
        x = self.pool(x).squeeze(-1)
        
        # 4. Classification
        x = self.dropout(x)
        x = self.fc(x)
        
        return x

      
__all__ = ["CNN", "INTERPOLATION_SIZE"]