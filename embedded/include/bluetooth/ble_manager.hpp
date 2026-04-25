#pragma once
#include <Arduino.h>

struct __attribute__((packed)) SensorPayload {
    uint32_t timestamp_ms;
    float bicep_pitch;
    float bicep_roll;
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
};

// expose to main.cpp
extern SensorPayload currentData;
extern bool deviceConnected;

void init_BLE();
void notify_BLE();