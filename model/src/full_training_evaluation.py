import os
import glob
import pandas as pd
import numpy as np

# Import your classes from the files we just made
from data_loader import JUIMUDataset
from inference import MovementQualityInference
from training import MovementTrainer

ROM_MOVEMENTS = ["ElbFlex", "ShFlex90", "ShHorAdd", "FrontSupPro"]
ADL_MOVEMENTS = ["TakePill", "PourWater", "BrushTeeth"]
ALL_MOVEMENTS = ROM_MOVEMENTS + ADL_MOVEMENTS
    
def gather_dataset(data_dir, movement_name):
    """
    Scans the directory for all files matching the movement name.
    Assigns Label 1 if the filename contains 'ND' and 0 if it contains 'Stroke'.
    """
    search_pattern = os.path.join(data_dir, f"*_{movement_name}.csv")
    all_files = glob.glob(search_pattern)
    
    if not all_files:
        raise ValueError(f"No files found for {movement_name} in {data_dir}. Check your path.")

    files = []
    labels = []
    
    for file_path in all_files:
        files.append(file_path)
        # Check filename for ND or Stroke
        if "_ND" in os.path.basename(file_path):
            labels.append(1)
        elif "_Stroke" in os.path.basename(file_path):
            labels.append(0)
            
    print(f"Gathered {len(files)} files for '{movement_name}' ({labels.count(1)} ND, {labels.count(0)} Stroke).")
    return files, labels

def full_training_evaluation(movement_name, *, debug=False):
    # ==========================================
    # 1. Setup & Data Gathering
    # ==========================================
    MODEL_PATH = "/home/ethan/projects/LAHacks2026/model/models/"
    
    if movement_name in ROM_MOVEMENTS:
        MODEL_TYPE = "ROM"
    elif movement_name in ADL_MOVEMENTS:
        MODEL_TYPE = "ADL"
    else:
        print(f'ERROR, movement_name unknown, ending training. Name was: {movement_name}')
        return
    
    DATA_PATH = "/home/ethan/projects/LAHacks2026/data/" + MODEL_TYPE + "/"
    # Get participant/patient info for the right model type
    PATIENT_INFO_PATH = "/home/ethan/projects/LAHacks2026/data/" + f"{MODEL_TYPE}_participants.csv"
    all_files, all_labels = gather_dataset(DATA_PATH, movement_name)
    
    if debug:
      print(f'All files: {all_files}')
      print(f'All labels: {all_labels}')
    
    # ==========================================
    # 2. Train / Test Split (Holdout Validation)
    # ==========================================
    # We will hold out the last 2 ND files and the last 2 Stroke files for testing.
    # The model will NEVER see these during training.
    nd_files = [f for f, l in zip(all_files, all_labels) if l == 1]
    stroke_files = [f for f, l in zip(all_files, all_labels) if l == 0]
    
    train_files = nd_files[:-2] + stroke_files[:-2]
    train_labels = [1] * len(nd_files[:-2]) + [0] * len(stroke_files[:-2])
    
    test_files = nd_files[-2:] + stroke_files[-2:]
    test_labels = [1, 1, 0, 0] # 2 ND, 2 Stroke
    
    if debug:
      print(f'Test files: {test_files}')
      print(f'Test labels: {test_labels}')
    
    print(f"Training on {len(train_files)} files. Testing on {len(test_files)} unseen files.")

    # ==========================================
    # 3. Full Training Cycle
    # ==========================================
    trainer = MovementTrainer(movement_name=movement_name, model_type=MODEL_TYPE)
    
    # Train for 40 epochs as per your architecture plan
    trainer.train(train_files, PATIENT_INFO_PATH, train_labels, epochs=40, batch_size=32)
    trainer.save_model(save_dir=MODEL_PATH)
    
    # ==========================================
    # 4. Score Verification (The Moment of Truth)
    # ==========================================
    print("\n" + "="*40)
    print("VERIFYING SCORES ON UNSEEN TEST DATA")
    print("="*40)
    
    weights_path = MODEL_PATH + f"{movement_name}_weights.pt"
    inference_engine = MovementQualityInference(movement_name=movement_name, model_weights_path=weights_path)
    
    test_dataset = JUIMUDataset(test_files, PATIENT_INFO_PATH, test_labels)
    # Keep track of how well the model did
    correct_cases = 0
    false_positives = 0
    false_negatives = 0
    for test_file, actual_label in zip(test_files, test_labels):
        # 1. Load the raw CSV exactly as the ESP32 will send it (Variable Length, 12 Channels)
        df = pd.read_csv(test_file)
        data_columns = test_dataset.get_patient_data(df, test_file)
        raw_sensor_data = df[data_columns].values
        
        # 2. Get the Live Score
        score = inference_engine.get_live_score(raw_sensor_data)
        
        # 3. Print Results
        patient_type = "HEALTHY (ND)" if actual_label == 1 else "IMPAIRED (Stroke)"
        filename = os.path.basename(test_file)
        
        print(f"File: {filename}")
        print(f"  -> Actual Patient: {patient_type}")
        print(f"  -> Model Score:    {score}/100")
        
        # A quick visual sanity check
        if actual_label == 1 and score > 70:
            print("  -> Result: PASS (Healthy score is appropriately high)")
            correct_cases += 1
        elif actual_label == 0 and score < 50:
            print("  -> Result: PASS (Impaired score is appropriately low)")
            correct_cases += 1
        elif actual_label == 1 and score <= 70:
            print("  -> Result: FAIL / INCONCLUSIVE (Score does not match expectations)")
            false_positives += 1
        elif actual_label == 0 and score >= 50:
            print("  -> Result: FAIL / INCONCLUSIVE (Score does not match expectations)")
            false_negatives += 1
    
        print("-" * 40)
        
    total_test_cases = len(test_files)
    print(f"Overall accuracy for {total_test_cases} test cases: {correct_cases}/{total_test_cases}); " +
          f"{100 * (correct_cases/total_test_cases)}% accuracy")
    
    # False positive is model inferring stroke when it was healthy, false negative is opposite
    return correct_cases, false_positives, false_negatives, total_test_cases

if __name__ == "__main__":
    total_correct = 0
    total_false_pos = 0
    total_false_neg = 0
    total_test_cases = 0
    
    for movement_name in ALL_MOVEMENTS:
        correct, false_pos, false_neg, tests = full_training_evaluation(movement_name)
        total_correct += correct
        total_false_pos += false_pos
        total_false_neg += false_neg
        total_test_cases += tests
        
    print(f"Overall overall accuracy for {total_test_cases} test cases: {total_correct}/{total_test_cases}); " +
          f"{100 * (total_correct/total_test_cases)}% accuracy")
    print(f"False positives: {false_positives}, false negatives: {false_negatives}")