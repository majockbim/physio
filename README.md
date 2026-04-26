# 🦾 Stroke Rehab System

**An end-to-end wearable IoT and Edge-AI platform for real-time stroke rehabilitation scoring.**

This project is a complete hardware-to-software pipeline designed to track, analyze, and gamify physical therapy for stroke patients. By combining custom dual-IMU wearables with a mobile-optimized 1D Convolutional Neural Network (CNN) running locally on iOS via **Zetic**, the system provides zero-latency movement quality scores and voice feedback.

## 🏗 High-Level Architecture

<img width="2058" height="691" alt="high_level_flowcart" src="https://github.com/user-attachments/assets/42c14b18-123f-416b-906d-5fbbe0a4f691" />

The system is divided into three core pillars:
1. **Embedded Hardware:** Captures raw 6-DOF human movement data at 80Hz.
2. **AI Scoring:** Processes the time-series data to evaluate movement quality.
3. **Swift App:** Manages the BLE connection, runs the Edge AI, and guides the patient.

---

## ⚙️ 1. Embedded Hardware (Data Generation)
The wearable component is built from the ground up for low latency and high data throughput, acting as the foundation for the AI model.

* **Microcontroller:** ESP32-C3 powered by a 4.8V LiPo battery.
* **Dual Sensors:** 2x MPU6050 (Bicep and Wrist). Both sensors run on a shared hardware I2C bus utilizing custom addressing (`0x68` for Bicep, `0x69` via AD0 pin for Wrist) to prevent collisions.
* **Diagnostics:** An integrated I2C OLED screen (`0x3C`) provides real-time device status and debugging.
* **Custom BLE Pipeline:** * The ESP32 calculates Delta Time (`dt`) to perform local math (Pitch, Roll, and Yaw integration) before transmission.
  * An expanded MTU size blasts a tightly packed **76-byte payload** over Bluetooth Low Energy (BLE) at **80Hz**.
  * Payload includes: `timestamp`, `bicep_PRY`, `wrist_PRY`, and raw `accel`/`gyro` channels for both sensors.

---

## 🧠 2. AI & Machine Learning (Zetic Edge Inference)
The AI pipeline evaluates movement quality by comparing patient data against the **JU-IMU dataset** (Stroke vs. Healthy subjects). The model is specifically optimized for small-dataset generalization and on-device export.

### Preprocessing & Signal Alignment
* **Side-Aware Selection:** Dynamically swaps sensor channels based on whether the patient has Left or Right hemiparesis, ensuring the affected limb always maps to the same input channels (resulting in a 12-channel input).
* **Global Normalization:** Uses a global $(x - \mu) / \sigma$ over all training time-steps rather than per-sample Z-scores. This is crucial as it preserves the cross-patient magnitude differences that distinguish weak stroke movements from healthy ones.
* **Interpolation:** Variable length movements are linearly interpolated to exactly **128 timesteps**.

### 1D CNN Architecture
The model utilizes a "shrink time, grow features" pattern suitable for continuous sensor streams:
* **Input:** `(Batch, 12, 128)`
* **Conv Blocks:** Three stride-2 blocks with progressively decreasing kernel sizes (7 → 5 → 3) to capture wide temporal context early and refine local features later. 
* **Mobile Optimizations:** Uses `BatchNorm` (highly stable on mobile vs. GroupNorm) and a fixed `AvgPool1d(kernel=16)` to avoid compatibility issues with mobile converters.
* **Output:** Generates a 0–100 movement quality score based on softmax confidence probabilities.

### Export to Zetic
The trained PyTorch model is packaged via `torch.export` into a deterministic `.pt2` graph, along with the saved global $\mu$ and $\sigma$ constants. This ensures identical preprocessing and ultra-fast local inference on the iOS client.

---

## 📱 3. Swift App (Frontend & Orchestration)
The iOS application serves as the command center for the patient, processing the hardware data and surfacing the AI insights.

* **Real-Time Monitor:** Uses `CoreBluetooth` to subscribe to the ESP32's custom characteristic, caching the 80Hz stream into 128-timestep sliding windows.
* **Local Inference via Zetic:** The Swift app holds the trained `.pt2` AI model. It passes the cached data window into the Zetic runtime, executing the CNN entirely on-device (no cloud computing delay).
* **Exercise Guide & Gamification:** Translates the AI's 0–100 movement quality score into a visual performance dashboard.
* **Audio Feedback:** Integrates **ElevenLabs TTS** to provide encouraging, real-time voice guidance to the patient based on their workout selection and current performance score.

<br>

Made with ❤️ for LA Hacks 2026 by [Mj](https://github.com/majockbim), [Ethan](https://github.com/ethan-pham25), [Scott](https://github.com/Scott170c), [Ian](https://github.com/YodaLightsabr)
