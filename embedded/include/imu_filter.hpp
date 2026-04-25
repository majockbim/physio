#pragma once
#include <Wire.h>
#include <Arduino.h>

#define MMA7660_ADDR 0x4C
#define MMA7660_X    0x00
#define MMA7660_MODE 0x07

class MMA7660Filter {
private:
    TwoWire* i2c_bus;
    float alpha;
    float filtered_pitch = 0.0;
    float filtered_roll = 0.0;
    bool sensor_connected = false;  // Track if sensor is working
    
    float readAxis(uint8_t reg) {
        if (!sensor_connected) return 0.0;  // Don't try if not connected
        
        i2c_bus->beginTransmission(MMA7660_ADDR);
        i2c_bus->write(reg);
        uint8_t error = i2c_bus->endTransmission(false);
        
        if (error != 0) {
            sensor_connected = false;  // Mark as disconnected
            return 0.0;
        }
        
        i2c_bus->requestFrom(MMA7660_ADDR, (uint8_t)1);
        
        if (i2c_bus->available()) {
            uint8_t raw = i2c_bus->read();
            uint8_t val = raw & 0x3F; 
            int8_t signed_val = val;
            if (signed_val > 31) signed_val -= 64; 
            return (float)signed_val;
        }
        return 0.0;
    }

public:
    MMA7660Filter(TwoWire* bus, float smoothing_factor = 0.10) {
        i2c_bus = bus;
        alpha = smoothing_factor; 
    }
    
    bool begin(int sda_pin, int scl_pin) {
        Serial.print("  Initializing I2C (SDA=");
        Serial.print(sda_pin);
        Serial.print(", SCL=");
        Serial.print(scl_pin);
        Serial.print(")...");
        
        i2c_bus->begin(sda_pin, scl_pin);
        i2c_bus->setTimeout(100);  // 100ms timeout to prevent hanging
        
        delay(10);  // Let bus stabilize
        
        // Try to initialize the sensor
        i2c_bus->beginTransmission(MMA7660_ADDR);
        i2c_bus->write(MMA7660_MODE);
        i2c_bus->write(0x01);
        uint8_t error = i2c_bus->endTransmission();
        
        if (error == 0) {
            sensor_connected = true;
            Serial.println(" OK");
            return true;
        } else {
            sensor_connected = false;
            Serial.print(" FAILED (error ");
            Serial.print(error);
            Serial.println(")");
            return false;
        }
    }
    
    void update() {
        if (!sensor_connected) return;  // Skip if sensor not working
        
        float ax = readAxis(0x00);
        float ay = readAxis(0x01);
        float az = readAxis(0x02);
        
        float raw_pitch = atan2(-ax, sqrt(ay * ay + az * az)) * (180.0 / PI);
        float raw_roll  = atan2(ay, az) * (180.0 / PI);
        
        filtered_pitch = (alpha * raw_pitch) + ((1.0 - alpha) * filtered_pitch);
        filtered_roll  = (alpha * raw_roll)  + ((1.0 - alpha) * filtered_roll);
    }
    
    float getPitch() { return filtered_pitch; }
    float getRoll() { return filtered_roll; }
    bool isConnected() { return sensor_connected; }
};
