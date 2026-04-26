#pragma once
#include <Wire.h>
#include <Arduino.h>

// Note: No more #define for the address here!
#define REG_GYRO_CONFIG      0x1B
#define REG_ACCEL_CONFIG     0x1C
#define REG_ACCEL_XOUT_H     0x3B
#define REG_PWR_MGMT_1       0x6B

#define GRAVITY 9.80665f
#define ACCEL_SENS_4G  (1.0f / 8192.0f)
#define GYRO_SENS_500  (1.0f / 65.5f)

struct AxisData {
    float x = 0;
    float y = 0;
    float z = 0;
};

class MPU6050Filter {
private:
    TwoWire* i2c_bus;
    uint8_t sensor_address; // The variable that holds the specific address
    float alpha;
    
    AxisData accel_filt;
    AxisData gyro_filt;
    float filtered_pitch = 0.0;
    float filtered_roll = 0.0;

public:
    // Constructor now takes the address as the second argument
    MPU6050Filter(TwoWire* bus, uint8_t address, float smoothing_factor = 0.50) {
        i2c_bus = bus;
        sensor_address = address; // Save the address for this specific sensor
        alpha = smoothing_factor; 
    }
    
    void begin(int sda_pin, int scl_pin) {
        // Only start the bus if it hasn't been started yet
        // (Though in your main.cpp we do Wire.begin() globally, which is great!)
        
        // 1. Wake up the sensor
        i2c_bus->beginTransmission(sensor_address);
        i2c_bus->write(REG_PWR_MGMT_1);
        i2c_bus->write(0x00); 
        i2c_bus->endTransmission();
        
        // 2. Configure Accel to 4G
        i2c_bus->beginTransmission(sensor_address);
        i2c_bus->write(REG_ACCEL_CONFIG);
        i2c_bus->write(0x08); 
        i2c_bus->endTransmission();
        
        // 3. Configure Gyro to 500dps
        i2c_bus->beginTransmission(sensor_address);
        i2c_bus->write(REG_GYRO_CONFIG);
        i2c_bus->write(0x08); 
        i2c_bus->endTransmission();
    }
    
    void update() {
        i2c_bus->beginTransmission(sensor_address);
        i2c_bus->write(REG_ACCEL_XOUT_H);
        i2c_bus->endTransmission(false);
        
        // Use the saved sensor_address variable
        i2c_bus->requestFrom((uint8_t)sensor_address, (uint8_t)14);
        
        if (i2c_bus->available() == 14) {
            // Read raw bytes and combine into 16-bit integers
            int16_t ax_raw = (i2c_bus->read() << 8) | i2c_bus->read();
            int16_t ay_raw = (i2c_bus->read() << 8) | i2c_bus->read();
            int16_t az_raw = (i2c_bus->read() << 8) | i2c_bus->read();
            
            i2c_bus->read(); i2c_bus->read(); // Skip temperature bytes
            
            int16_t gx_raw = (i2c_bus->read() << 8) | i2c_bus->read();
            int16_t gy_raw = (i2c_bus->read() << 8) | i2c_bus->read();
            int16_t gz_raw = (i2c_bus->read() << 8) | i2c_bus->read();
            
            // Convert Accel to m/s^2 (Includes Gravity)
            float ax_ms2 = (ax_raw * ACCEL_SENS_4G) * GRAVITY;
            float ay_ms2 = (ay_raw * ACCEL_SENS_4G) * GRAVITY;
            float az_ms2 = (az_raw * ACCEL_SENS_4G) * GRAVITY;
            
            // Convert Gyro to degrees per second
            float gx_dps = gx_raw * GYRO_SENS_500;
            float gy_dps = gy_raw * GYRO_SENS_500;
            float gz_dps = gz_raw * GYRO_SENS_500;
            
            // Apply Low-Pass Filter to Accel
            accel_filt.x = (alpha * ax_ms2) + (1.0f - alpha) * accel_filt.x;
            accel_filt.y = (alpha * ay_ms2) + (1.0f - alpha) * accel_filt.y;
            accel_filt.z = (alpha * az_ms2) + (1.0f - alpha) * accel_filt.z;
            
            // Apply Low-Pass Filter to Gyro
            gyro_filt.x = (alpha * gx_dps) + (1.0f - alpha) * gyro_filt.x;
            gyro_filt.y = (alpha * gy_dps) + (1.0f - alpha) * gyro_filt.y;
            gyro_filt.z = (alpha * gz_dps) + (1.0f - alpha) * gyro_filt.z;
            
            // Calculate Pitch & Roll from filtered Accel
            float raw_pitch = atan2(-accel_filt.x, sqrt(accel_filt.y * accel_filt.y + accel_filt.z * accel_filt.z)) * (180.0 / PI);
            float raw_roll  = atan2(accel_filt.y, accel_filt.z) * (180.0 / PI);
            
            filtered_pitch = (alpha * raw_pitch) + ((1.0 - alpha) * filtered_pitch);
            filtered_roll  = (alpha * raw_roll)  + ((1.0 - alpha) * filtered_roll);
        }
    }
    
    float getPitch() { return filtered_pitch; }
    float getRoll() { return filtered_roll; }
    AxisData getAccel() { return accel_filt; }
    AxisData getGyro() { return gyro_filt; }
};