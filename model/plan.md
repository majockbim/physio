# Plan: Build 1-D CNN for IMU-based Stroke Rehab Movement Quality Scoring

## TL;DR
Build 6 separate 1-D CNN models (PyTorch) to classify movement quality for stroke rehab. Each model analyzes 12-channel IMU time-series (2 sensors × 6 channels) using linear interpolation to normalize variable-length segments into 20 fixed windows. Train on ND (healthy) + Stroke patient data with ND+Stroke combined training yielding best generalization. Export as ONNX/.pt2 for iOS integration.

## Context
- **Dataset**: JU-IMU (Jeonju University IMU) - published dataset with 29 ND and 15 Stroke patients
- **Data structure**: 5 IMU sensors (45 channels total), but using subset: 2 sensors with acc+gyro (12 channels total)
- **Reference implementation**: Paper "Investigating Activity Recognition for Hemiparetic Stroke Patients Using Wearable Sensors: A Deep Learning Approach with Data Augmentation" (2024)
- **Goal**: Live quality score (0-100) = softmax probability × 100 for "healthy" class vs "affected" class

## Clarifications Made
✓ Classification: Binary per movement instance (ND vs Stroke) → probability score
✓ Model structure: 7 separate models
✓ Sensors: Right wrist (sensor 1) + right upper arm (sensor 4)
✓ Movements: 7 total:
  - ADL (3): TakePill, PourWater, BrushTeeth
  - Note: ROM movements (ElbFlex, ShldFlex, ShldAbd, FrontSupinationPronation) not available in current dataset
✓ Input features: 2 sensors (RW + RUA), gyro + accel only (12 channels, no magnetometer)
✓ Windowing: Linear interpolation → 20 windows per segment
✓ Train/val/test: Per-participant split (LOSO-CV on Stroke group)
✓ Export format: ONNX or .pt2
✓ Quality score: Per-participant baseline (each person gets individualized threshold)

## Steps

### Phase 1: Data Pipeline & Preprocessing
1. **Load and filter data** ✓ COMPLETE
   - Parse CSVs from `data/ADL/` folder
   - Extract only ND and Stroke participant data
   - Filter to 7 movements of interest (map ADL file names to movement labels)
   - Extract 2 sensors (determine which sensors from paper methodology)
   - Keep only 6 channels per sensor (acc_x, acc_y, acc_z, gyro_x, gyro_y, gyro_z)
   - Remove magnetometer channels

2. **Implement linear interpolation & windowing** ✓ COMPLETE
   - For each movement segment (variable length), interpolate to fixed length (ROM~1000 points, ADL~3700 points)
   - Apply sliding window to produce exactly 20 windows per segment
   - Output: (num_segments, 20, 12) tensors where 12 = 2 sensors × 6 channels

3. **Create labels** ✓ COMPLETE
   - Binary labels: 0 = Stroke (affected), 1 = ND (healthy)
   - Organize by participant and movement type

4. **Create data loaders** ✓ COMPLETE
   - Per-participant split: leave-one-subject-out cross-validation (LOSO-CV) on Stroke group
   - Stratify by ND/Stroke group
   - Train: ND + most Stroke, Val: 10%, Test: 1 held-out Stroke participant

### Phase 2: Model Architecture
5. **Define 1-D CNN architecture** (*independent*)
   - Input: (batch, 20 windows, 12 channels)
   - Process: 4 conv layers (kernel_size=5, stride=2) with increasing filters (32→64→128→256)
   - Feature extraction: Conv layers output progressively smaller features
   - Classification: 2 dense layers (800, 200 neurons) + softmax output (2 classes)
   - Regularization: Dropout (p=0.7) after dense layers
   - Activation: ReLU for conv/dense, softmax for output

6. **Implement data augmentation** (*after Step 5*)
   - Axis rotation: rotate IMU sensor vectors by random angle (−90° to +90°) on random axis
   - Apply during training only (augment ND+Stroke combined dataset)

### Phase 3: Training
7. **Set up training infrastructure** (*after Phase 1 + Step 5*)
   - Optimizer: AdamW (lr=0.001, weight_decay=0.01)
   - Loss: Cross-entropy (binary classification)
   - Batch size: 256 windows
   - Epochs: 40
   - Metrics: F1-score per movement per participant

8. **Train 6 models separately** (*depends on Steps 5-7*)
   - Model 1-4: ROM movements (ElbFlex, ShldFlex, ShldAbd, SupinationPronation)
   - Model 5-7: ADL movements (TakePill, PourWater, BrushTeeth)
   - Training condition: ND + Stroke combined (paper shows best F1-score)
   - Evaluation: LOSO-CV on Stroke group

### Phase 4: Export & Integration
9. **Export models to ONNX/.pt2** (*after Step 8*)
   - Convert trained PyTorch models to ONNX format
   - Verify inference correctness on test set
   - Document model input/output shapes

10. **Create inference wrapper** (*after Step 9*)
    - Score computation: softmax(model output)[1] × 100 (healthy class probability)
    - Return quality score (0-100) + movement confidence
    - Prepare for iOS integration (Zetic will handle app side)

### Phase 5: Evaluation & Validation
11. **Evaluate model performance** (*after Step 8*)
    - Report F1-scores per movement per participant (separate ND vs Stroke)
    - Asymmetry analysis: compare F1-scores for UNI vs BIA vs BIS movements
    - Confusion matrices: identify which movements get confused
    - Baseline: F1-score on single sensor (wrist only) for practical smartwatch feasibility

12. **Validate quality score interpretation** (*after Step 10*)
    - Confirm 0-100 scale maps to movement quality (ND=higher, Stroke=lower)
    - Test edge cases and failure modes

## Relevant Files
- `data/ADL/` — input CSV files with raw IMU data
- `data/` — will contain preprocessed datasets (numpy/torch format)
- `model/` — will contain trained .pt and exported .onnx models
- `src/data_loader.py` — data pipeline (linear interpolation, windowing, labels)
- `src/model.py` — 1-D CNN architecture
- `src/train.py` — training loop with LOSO-CV
- `src/inference.py` — inference wrapper for quality scoring
- `scripts/evaluate.py` — evaluation metrics and visualization

## Verification
1. Data pipeline: Load 1 ADL CSV, verify 20 windows × 12 channels output
2. Model: Forward pass with synthetic (batch=2, windows=20, channels=12) tensor → (2, 2) logits
3. Training: Run 1 epoch on toy subset, loss decreases
4. LOSO-CV: Train on N-1 Stroke participants, evaluate on 1 held-out
5. Export: Load ONNX in Python, compare inference output to PyTorch
6. Quality score: Verify ND samples → higher scores, Stroke samples → lower scores (on average)

## Status
- ✓ COMPLETE: Created comprehensive inference module (src/inference.py) for Phase 4, Step 10
- Data structure confirmed: 5 sensors × 9 channels per sensor (45 total)
- Using sensors 1 + 4, channels 0-5 (acc_x, acc_y, acc_z, gyro_x, gyro_y, gyro_z) = 12 channels total

## Completed Modules
- `src/inference.py` ✓ - MovementQualityInference class with:
  - Model loading from .pt checkpoints
  - Variable-length input preprocessing (linear interpolation + windowing)
  - Per-participant baseline normalization
  - Real-time scoring (0-100 scale)
  - Batch processing support
  - ONNX export for iOS
  - Error handling and validation
  - Benchmark utilities

## Decisions
- **6 separate models** vs 1 unified: Separate for simplicity and per-movement fine-tuning
- **ND+Stroke training** vs Stroke-only: Paper shows 31.6% F1-score improvement with combined training
- **Axis rotation augmentation** vs others: Simulates natural variability in hand orientation
- **Per-participant split** vs temporal: Prevents information leakage and realistic evaluation for stroke patients
- **Binary classification (ND vs Stroke)** as proxy for quality: Direct and interpretable; score = P(ND|movement)

## Implementation Status: ✅ COMPLETE

All core modules built and ready for training/deployment.

### File Structure
```
/home/ethan/projects/LAHacks2026/
├── data/                     # Raw IMU CSV files
├── results/                  # Training logs & evaluation results
├── model/src/
│   ├── data_loader.py       # Data pipeline, preprocessing, LOSO-CV ✅
│   ├── model.py              # 1-D CNN architecture ✅
│   ├── train.py              # Training loop with LOSO-CV ✅
│   └── inference.py          # Real-time scoring & iOS export ✅
├── requirements.txt          # Dependencies ✅
├── main.py                   # CLI entry point ✅
└── README.md                 # Documentation (run: python main.py --help)
```

### How to Train (Next Steps)
```bash
# 1. Install dependencies
pip install -r requirements.txt

# 2. Run training (trains 3 models: TakePill, PourWater, BrushTeeth)
python main.py --train

# 3. Evaluate results
python main.py --evaluate

# 4. Try live inference
python main.py --infer --model TakePill --participant Stroke2

# 5. Export to ONNX for iOS
python main.py --export --format onnx
```

### Key Architecture Details
- **Input**: Variable-length IMU buffers (sensors 1 & 4, 12 channels each)
- **Processing**: Linear interpolation → 20 fixed windows → 1-D CNN
- **Output**: Quality score 0-100 per participant, per movement
- **LOSO-CV**: Leave-one-Stroke-out cross-validation (14 folds)
- **Data**: 28 ND + 14 Stroke participants, 3 movements

### Ready for Integration
- Models export to ONNX for Zetic iOS integration
- `src/inference.py` handles real-time scoring with participant personalization
- Training pipeline generates per-participant baselines for normalization
- JSON results with F1-scores, accuracy, and per-fold metrics
