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

    float readAxis(uint8_t reg) {
        i2c_bus->beginTransmission(MMA7660_ADDR);
        i2c_bus->write(reg);
        i2c_bus->endTransmission(false);
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

    void begin(int sda_pin, int scl_pin) {
        i2c_bus->begin(sda_pin, scl_pin);
        i2c_bus->beginTransmission(MMA7660_ADDR);
        i2c_bus->write(MMA7660_MODE);
        i2c_bus->write(0x01); 
        i2c_bus->endTransmission();
    }

    void update() {
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
};