# Physio

An arm-worn prototype for exploring stroke rehabilitation feedback, built with an ESP32-C3, two motion sensors, and an iOS app.

We built the first version at LA Hacks 2026 in 36 hours. Sensors on the bicep and wrist send movement data to the phone over Bluetooth. The app lets you choose exercises, records movement, and runs a small neural network on the phone to produce a score.

<p align="center">
  <img src="assets/photos/sleeve-prototype.jpg" width="540" alt="The original Physio sleeve worn on an arm during elbow flexion" />
</p>

*The hackathon prototype, with sensors on the bicep and wrist.*

**[Watch the hardware demo (Esp32.mp4)](https://github.com/majockbim/physio/releases/tag/v0.1.0#demo-spin)** · [Devpost build story](https://devpost.com/software/strokr-ai) · [Original hackathon release](https://github.com/majockbim/physio/releases/tag/v0.1.0)

The breadboard sits on the bicep and takes up a lot of space. After the hackathon, I (Majock) designed a two-layer carrier PCB in Altium to reduce the jumper wiring and make the assembly more compact. PCBWay reached out after seeing the project and sponsored the next hardware iteration.

**Current status:** the original prototype is demonstrated above. PCBWay has sent factory photos of the custom boards; they have not arrived yet, so I have not tested the PCB assembly. Physio is a development prototype, and its score has not been validated as a clinical measure.

## How it works

```text
Bicep + wrist IMUs → ESP32-C3 → Bluetooth LE → iOS app → on-device score
```

### Sensing and Bluetooth

The two MPU6050 modules share an I²C bus. They use different addresses (`0x68` and `0x69`) so the ESP32 can read both. An SSD1306 OLED gives us a simple way to check the hardware while debugging.

The firmware packs a timestamp, accelerometer and gyroscope readings, and estimated pitch/roll/yaw for both sensors into a **76-byte BLE notification**. The prototype targets roughly **80 updates per second**; the current loop uses a 12 ms interval, so actual throughput depends on sensor reads, serial logging, and the BLE connection.

The [firmware](embedded/src/main.cpp) and [packet definition](embedded/include/bluetooth/ble_manager.hpp) are small enough to follow directly. The app decodes the same layout in [BLEManager.swift](app/Stroke%20Rehab/BLEManager.swift).

### The app

<p align="center">
  <img src="assets/photos/ios-app.png" width="280" alt="Physio iOS home screen showing recent exercise sessions and scores" />
</p>

The Swift app connects through CoreBluetooth, shows live sensor data, lets you select exercises, and saves session results. Exercise recordings are passed to the model for scoring. There is also a developer view for inspecting the incoming data and running inference.

Inference runs on the phone through **Zetic MLange**. The app loads the configured model through the Zetic SDK, which can require a download. Optional spoken feedback uses **ElevenLabs over the network**, sending the text to be spoken. Local inference and network-based speech are separate parts of the app.

### What the score means

The model is a PyTorch 1D CNN trained using the [JU-IMU dataset](https://github.com/youngminoh7/JU-IMU). It classifies recordings into the dataset's stroke and healthy classes. The app displays `Int(P(healthy) × 100)` as the prototype's score; it is not a percentage of recovery or a validated assessment of exercise form.

For each recording, the app takes 12 accelerometer/gyroscope channels, applies the saved per-channel training mean and standard deviation, and interpolates to 128 timesteps. Three convolution blocks feed a two-class output. Training uses side-aware sensor selection to choose the affected limb; live inference expects wrist channels followed by bicep channels.

The main implementation details are in [the CNN](model/src/cnn.py), [training data preparation](model/src/data_loader.py), and [the Swift inference pipeline](app/Stroke%20Rehab/MovementQualityInference.swift).

## References

- Oh et al. (2024), *Investigating Activity Recognition for Hemiparetic Stroke Patients Using Wearable Sensors: A Deep Learning Approach with Data Augmentation*. [Paper](https://doi.org/10.3390/s24010210) · [JU-IMU dataset](https://github.com/youngminoh7/JU-IMU).
- [MPU-6050 product specification](https://cdn.sparkfun.com/datasheets/Sensors/Accelerometers/RM-MPU-6000A.pdf).

## People

The LA Hacks prototype was built by [Majock Bim](https://github.com/majockbim), [Ethan Pham](https://github.com/ethan-pham25), [Scott Chiang](https://github.com/Scott170c), and [Ian Madden](https://github.com/YodaLightsabr). The custom PCB is Majock's post-hackathon hardware iteration.
