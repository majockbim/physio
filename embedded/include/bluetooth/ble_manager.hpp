#pragma once
#include <Arduino.h>

struct __attribute__((packed)) SensorPayload {
    uint32_t timestamp_ms;
    
    float bicep_pitch;
    float bicep_roll;
    float wrist_pitch;
    float wrist_roll;
    float wrist_yaw;
    
    float bicep_accel_x;
    float bicep_accel_y;
    float bicep_accel_z;
    float bicep_gyro_x;
    float bicep_gyro_y;
    float bicep_gyro_z;

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