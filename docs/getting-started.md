# Working with the prototype

These notes describe the checked-in project configuration. They are not a confirmation that the custom PCB has been brought up; that is still pending delivery.

## ESP32 firmware

Use PlatformIO with the environment in [platformio.ini](../embedded/platformio.ini). It targets `esp32-c3-devkitm-1`, uses the Arduino framework, and pins the Espressif32 platform to `6.5.0`.

From the repository root, with the PlatformIO CLI installed:

```sh
cd embedded
pio run
pio run --target upload
pio device monitor --baud 115200
```

The upload command requires a connected, compatible ESP32-C3 board. Check its pinout against the wiring: the firmware uses GPIO 5 for SDA and GPIO 6 for SCL. Both IMUs share this bus, along with the OLED at `0x3C`.

The firmware advertises as `ESP32_Arm_Tracker`. Its current sensor constructors assign bicep to `0x69` and wrist to `0x68`; some comments and serial messages still show the opposite mapping. Confirm the physical sensor roles before using a recording for inference. See the [hardware notes](../hardware/README.md) before wiring the new carrier.

## iOS app

1. On a Mac, open [Stroke Rehab.xcodeproj](../app/Stroke%20Rehab.xcodeproj) in Xcode. The checked-in deployment target is iOS 18.1.
2. Resolve Swift packages. The lockfile pins Zetic MLange iOS to version `1.6.0`.
3. Choose your signing team and a physical iPhone for BLE testing.
4. Configure your own Zetic access and model settings in [RepScorer.swift](../app/Stroke%20Rehab/RepScorer.swift). The repository contains a placeholder personal key; the model name and version must point to a model you can access with matching inputs and outputs.
5. If you want spoken feedback, configure your own ElevenLabs key in [SpeechManager.swift](../app/Stroke%20Rehab/SpeechManager.swift). Keep credentials out of commits. Speech sends text to ElevenLabs and needs network access.
6. Run the app, allow Bluetooth access, connect to `ESP32_Arm_Tracker`, and inspect the sensor data before recording an exercise.

The model may need to download when it is first loaded. Scoring then executes through the Zetic runtime on the phone. If you retrain the model, update the preprocessing constants in [MovementQualityInference.swift](../app/Stroke%20Rehab/MovementQualityInference.swift) to match the exported model's channel order, mean, and standard deviation.

## Model training

The source is under [model/src/](../model/src/). Dataset files and generated model weights are excluded from Git. Obtain the [JU-IMU dataset](https://github.com/youngminoh7/JU-IMU) separately and review its usage terms.

[full_training_evaluation.py](../model/src/full_training_evaluation.py) still contains developer-specific absolute dataset paths. Update those paths for your machine before attempting to train. The model code imports PyTorch, NumPy, and pandas; the current `pyproject.toml` does not declare a complete reproducible training environment.

[training.py](../model/src/training.py) includes the model export and normalization-statistics output. Keep the model and its statistics together when deploying to the app.

[Back to the project README](../README.md)
