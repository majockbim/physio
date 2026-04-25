from src.data_loader import JUIMUDataset
import torch

# --- Verification Script ---
if __name__ == "__main__":
    # Create a dummy list pointing to one of your real ADL CSV files
    # 1 = ND (Healthy), 0 = Stroke
    sample_files = ["/home/ethan/projects/LAHacks2026/data/ROM/ROM_ND4_ElbFlex.csv"] 
    sample_labels = [1] 

    # Initialize the dataset
    test_dataset = JUIMUDataset(sample_files, sample_labels)
    
    # Load the first item
    features, label = test_dataset[0]
    
    print("=== Verification Check ===")
    print(f"Expected Feature Shape: torch.Size([20, 12])")
    print(f"Actual Feature Shape:   {features.shape}")
    print(f"Label Shape:            {label.shape}")
    print(f"Label Value:            {label.item()}")
    print(f'Features Value:         {features}')
    
    # Check if interpolation created any NaNs
    if torch.isnan(features).any():
        print("WARNING: NaN values detected in tensor. Check your CSV for missing data.")
    else:
        print("Data is clean. Ready for Phase 2: 1-D CNN Architecture.")