from src.training import MovementTrainer 

if __name__ == "__main__":
    DATA_PATH = "/home/ethan/projects/LAHacks2026/data/"
    adl_patient_path = DATA_PATH + 'ADL_participants.csv'
    rom_patient_path = DATA_PATH + 'ROM_participants.csv'
    save_path = "model/test/models/"
    
    # ---------------------------------------------------------
    # Example 1: Training a Complex ADL Model (Toothbrushing)
    # ---------------------------------------------------------
    # In reality, you will generate these lists by scanning your 'data/ADL/' directory
    mock_brush_files = [
      DATA_PATH + "/ADL/ADL_ND4_BrushTeeth.csv", 
      DATA_PATH + "/ADL/ADL_Stroke16_BrushTeeth.csv", 
    ]
    mock_brush_labels = [1, 0] # 1 for ND, 0 for Stroke
    
    brush_trainer = MovementTrainer(movement_name="BrushTeeth", model_type="ADL", debug=True)
    
    # Run training (Set epochs low for testing, bump to 40 for real run)
    brush_trainer.train(mock_brush_files, adl_patient_path, mock_brush_labels, epochs=40, batch_size=32)
    
    # Save the .pt file!
    brush_trainer.save_model(save_path)


    # ---------------------------------------------------------
    # Example 2: Training a Simple ROM Model (Elbow Flexion)
    # ---------------------------------------------------------
    mock_flex_files = [
        DATA_PATH + "ROM/ROM_ND4_ElbFlex.csv",
        DATA_PATH + "ROM/ROM_Stroke16_ElbFlex.csv",
    ]
    mock_flex_labels = [1, 0] 
    
    flex_trainer = MovementTrainer(movement_name="ElbFlex", model_type="ROM", debug=True)
    flex_trainer.train(mock_flex_files, rom_patient_path, mock_flex_labels, epochs=40, batch_size=32)
    flex_trainer.save_model(save_path)