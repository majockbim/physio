from src.data_loader import JUIMUDataset
import torch

# --- Verification Script ---
if __name__ == "__main__":
    # Create a dummy list pointing to some of the real CSV files
    DATA_PATH = "/home/ethan/projects/LAHacks2026/data/"
    sample_files = [
        DATA_PATH + "ROM/ROM_ND4_ElbFlex.csv",
        DATA_PATH + "ROM/ROM_Stroke15_ElbFlex.csv"
    ] 
    patient_info_path = DATA_PATH + 'ROM_participants.csv'
    # 1 = ND (Healthy), 0 = Stroke
    sample_labels = [1, 0] 

    # Initialize the dataset
    test_dataset = JUIMUDataset(sample_files, patient_info_path, sample_labels, debug = True)
    
    # Load the first item
    for patient in test_dataset:
        features, label = patient
        
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