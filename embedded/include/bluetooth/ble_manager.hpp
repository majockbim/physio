#pragma once
#include <Arduino.h>

struct __atribute__((packed)) SensorPayload {
    float bicep_pitch;
    float bicel_roll;
    float wrist_pitch;
    float wrist_roll;
    /* for new IMU (future)
    uint32_t timestamp_ms; // tell swift when data was recorded (may need for 80Hz goal)

    float bicep_accel_x
    float bicep_accel_y
    float bicep_accel_z
    float bicep_gyro_x
    float bicep_gyro_y
    float bicep_gyro_z

    float wrist_accel_x
    float wrist_accel_y
    float wrist_accel_z
    float wrist_gyro_x
    float wrist_gyro_y
    float wrist_gyro_z
    */
}

// expose to main.cpp
extern SensorPayloard currentData;
extern bool deviceConnected;

void init_BLE();
void notify_BLE();