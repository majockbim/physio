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
    # We will hold out test_count ND files and test_count Stroke files for testing.
    # The model will NEVER see these during training.
    # Shuffle to avoid filesystem-order bias.
    test_count = 3
    nd_files = [f for f, l in zip(all_files, all_labels) if l == 1]
    stroke_files = [f for f, l in zip(all_files, all_labels) if l == 0]
    
    np.random.seed(42)  # Reproducible split
    np.random.shuffle(nd_files)
    np.random.shuffle(stroke_files)
    
    train_files = nd_files[:-test_count] + stroke_files[:-test_count]
    train_labels = [1] * len(nd_files[:-test_count]) + [0] * len(stroke_files[:-test_count])
    
    test_files = nd_files[-test_count:] + stroke_files[-test_count:]
    test_labels = [1] * test_count + [0] * test_count
    
    if debug:
      print(f'Test files: {test_files}')
      print(f'Test labels: {test_labels}')
    
    print(f"Training on {len(train_files)} files. Testing on {len(test_files)} unseen files.")

    # ==========================================
    # 3. Full Training Cycle
    # ==========================================
    trainer = MovementTrainer(movement_name=movement_name, model_type=MODEL_TYPE)
    
    trainer.train(train_files, PATIENT_INFO_PATH, train_labels, epochs=60, batch_size=16)
    trainer.save_model(save_dir=MODEL_PATH)
    
    # ==========================================
    # 4. Score Verification (The Moment of Truth)
    # ==========================================
    print("\n" + "="*40)
    print("VERIFYING SCORES ON UNSEEN TEST DATA")
    print("="*40)
    
    # Inference uses standard PyTorch dict, not mobile .pt2 export
    weights_path = MODEL_PATH + f"{movement_name}_weights.pt"
    inference_engine = MovementQualityInference(movement_name=movement_name, model_weights_path=weights_path)
    
    test_dataset = JUIMUDataset(test_files, PATIENT_INFO_PATH, test_labels)
    # Keep track of how well the model did
    correct_binary = 0    # Standard: healthy > 50, stroke <= 50
    correct_strict = 0    # Strict: healthy > 70, stroke < 50
    false_positives = 0
    false_negatives = 0
    nd_scores = []
    stroke_scores = []
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
        
        if actual_label == 1:
            nd_scores.append(score)
        else:
            stroke_scores.append(score)
        
        # Binary accuracy (>50 threshold)
        predicted_healthy = score > 50
        actually_healthy = actual_label == 1
        if predicted_healthy == actually_healthy:
            correct_binary += 1
        
        print(f"File: {filename}")
        print(f"  -> Actual Patient: {patient_type}")
        print(f"  -> Model Score:    {score}/100")
        
        # Strict quality thresholds
        if actual_label == 1 and score > 70:
            print("  -> Result: PASS (Healthy score is appropriately high)")
            correct_strict += 1
        elif actual_label == 0 and score < 50:
            print("  -> Result: PASS (Impaired score is appropriately low)")
            correct_strict += 1
        elif actual_label == 1 and score <= 70:
            print("  -> Result: FAIL / INCONCLUSIVE (Score does not match expectations)")
            false_positives += 1
        elif actual_label == 0 and score >= 50:
            print("  -> Result: FAIL / INCONCLUSIVE (Score does not match expectations)")
            false_negatives += 1
    
        print("-" * 40)
        
    total_test_cases = len(test_files)
    binary_acc = 100 * correct_binary / total_test_cases
    strict_acc = 100 * correct_strict / total_test_cases
    nd_avg = np.mean(nd_scores) if nd_scores else 0
    stroke_avg = np.mean(stroke_scores) if stroke_scores else 0
    
    print(f"Binary accuracy (>50 threshold): {correct_binary}/{total_test_cases} = {binary_acc:.1f}%")
    print(f"Strict accuracy (>70/ND, <50/Stroke): {correct_strict}/{total_test_cases} = {strict_acc:.1f}%")
    print(f"Avg ND score: {nd_avg:.1f}, Avg Stroke score: {stroke_avg:.1f}, Gap: {nd_avg - stroke_avg:.1f}")
    
    # False positive is model inferring stroke when it was healthy, false negative is opposite
    return correct_binary, false_positives, false_negatives, total_test_cases

def unified_training_evaluation(*, debug=False):
    """
    Train a SINGLE model on ALL movements (~245 samples) instead of per-movement models (~35 each).
    Uses patient-level split: all movements for a held-out patient go to test.
    """
    MODEL_PATH = "/home/ethan/projects/LAHacks2026/model/models/"
    DATA_BASE = "/home/ethan/projects/LAHacks2026/data/"
    
    # ==========================================
    # 1. Gather ALL data across all movements
    # ==========================================
    all_files = []
    all_labels = []
    all_patient_info_paths = []  # Per-file patient info path
    
    for movement_name in ALL_MOVEMENTS:
        if movement_name in ROM_MOVEMENTS:
            data_dir = DATA_BASE + "ROM/"
            info_path = DATA_BASE + "ROM_participants.csv"
        else:
            data_dir = DATA_BASE + "ADL/"
            info_path = DATA_BASE + "ADL_participants.csv"
        
        files, labels = gather_dataset(data_dir, movement_name)
        all_files.extend(files)
        all_labels.extend(labels)
        all_patient_info_paths.extend([info_path] * len(files))
    
    print(f"\nTotal: {len(all_files)} files ({all_labels.count(1)} ND, {all_labels.count(0)} Stroke)")
    
    # ==========================================
    # 2. Patient-level split (no leakage)
    # ==========================================
    # Extract patient IDs and group by patient
    def get_patient_id(filepath):
        return os.path.basename(filepath).split('_')[1]
    
    # Get unique patient IDs per class
    nd_patients = sorted(set(get_patient_id(f) for f, l in zip(all_files, all_labels) if l == 1))
    stroke_patients = sorted(set(get_patient_id(f) for f, l in zip(all_files, all_labels) if l == 0))
    
    np.random.seed(42)
    np.random.shuffle(nd_patients)
    np.random.shuffle(stroke_patients)
    
    # Hold out 3 ND + 3 Stroke patients (all their movements go to test)
    test_patient_count = 3
    test_patients = set(nd_patients[-test_patient_count:] + stroke_patients[-test_patient_count:])
    
    train_files, train_labels, train_info_paths = [], [], []
    test_files, test_labels, test_info_paths = [], [], []
    
    for f, l, info in zip(all_files, all_labels, all_patient_info_paths):
        pid = get_patient_id(f)
        if pid in test_patients:
            test_files.append(f)
            test_labels.append(l)
            test_info_paths.append(info)
        else:
            train_files.append(f)
            train_labels.append(l)
            train_info_paths.append(info)
    
    print(f"Train: {len(train_files)} files | Test: {len(test_files)} files")
    print(f"Test patients: {test_patients}")
    
    # ==========================================
    # 3. Train unified model
    # ==========================================
    trainer = MovementTrainer(movement_name="Unified", model_type="ROM")
    trainer.train(train_files, train_info_paths, train_labels, epochs=60, batch_size=32)
    trainer.save_model(save_dir=MODEL_PATH)
    
    # ==========================================
    # 4. Evaluate on held-out patients
    # ==========================================
    print("\n" + "="*50)
    print("UNIFIED MODEL — UNSEEN PATIENT EVALUATION")
    print("="*50)
    
    weights_path = MODEL_PATH + "Unified_weights.pt"
    # Use a valid movement name for loading (architecture is the same)
    inference_engine = MovementQualityInference(movement_name="ElbFlex", model_weights_path=weights_path)
    
    test_dataset = JUIMUDataset(test_files, test_info_paths, test_labels)
    
    correct_binary = 0
    nd_scores = []
    stroke_scores = []
    # Track per-movement results
    movement_results = {}
    
    for i, (test_file, actual_label) in enumerate(zip(test_files, test_labels)):
        df = pd.read_csv(test_file)
        data_columns = test_dataset.get_patient_data(df, test_file, test_info_paths[i])
        raw_sensor_data = df[data_columns].values
        
        score = inference_engine.get_live_score(raw_sensor_data)
        
        filename = os.path.basename(test_file)
        patient_type = "ND" if actual_label == 1 else "Stroke"
        # Extract movement name from filename
        movement = filename.rsplit('_', 1)[1].replace('.csv', '')
        
        if actual_label == 1:
            nd_scores.append(score)
        else:
            stroke_scores.append(score)
        
        predicted_healthy = score > 50
        actually_healthy = actual_label == 1
        correct = predicted_healthy == actually_healthy
        if correct:
            correct_binary += 1
        
        # Track per-movement
        if movement not in movement_results:
            movement_results[movement] = {'correct': 0, 'total': 0}
        movement_results[movement]['total'] += 1
        if correct:
            movement_results[movement]['correct'] += 1
        
        result = "✓" if correct else "✗"
        print(f"  {result} {filename:40s} | {patient_type:6s} | Score: {score:3d}/100")
    
    total = len(test_files)
    binary_acc = 100 * correct_binary / total
    nd_avg = np.mean(nd_scores) if nd_scores else 0
    stroke_avg = np.mean(stroke_scores) if stroke_scores else 0
    
    print(f"\n{'='*50}")
    print(f"OVERALL: {correct_binary}/{total} = {binary_acc:.1f}% binary accuracy")
    print(f"Avg ND score: {nd_avg:.1f} | Avg Stroke score: {stroke_avg:.1f} | Gap: {nd_avg - stroke_avg:.1f}")
    print(f"\nPer-movement breakdown:")
    for mov, res in sorted(movement_results.items()):
        acc = 100 * res['correct'] / res['total'] if res['total'] > 0 else 0
        print(f"  {mov:15s}: {res['correct']}/{res['total']} = {acc:.0f}%")
    
    return correct_binary, total


if __name__ == "__main__":
    # Run unified model by default
    unified_training_evaluation()