#include <Arduino.h>
#include "../include/imu/imu_filter.hpp"

// bicep uses hardware I2C
MMA7660Filter bicepIMU(&Wire, 0.10);

// wrist sensor: custom bit-banged I2C
const int WRIST_SDA = 8;
const int WRIST_SCL = 9;

float wrist_pitch = 0.0;
float wrist_roll = 0.0;
const float ALPHA = 0.10;

// bit-bang I2C functions
void i2c_start() {
    pinMode(WRIST_SDA, OUTPUT);
    pinMode(WRIST_SCL, OUTPUT);
    digitalWrite(WRIST_SDA, HIGH);
    digitalWrite(WRIST_SCL, HIGH);
    delayMicroseconds(5);
    digitalWrite(WRIST_SDA, LOW);
    delayMicroseconds(5);
    digitalWrite(WRIST_SCL, LOW);
}

void i2c_stop() {
    pinMode(WRIST_SDA, OUTPUT);
    digitalWrite(WRIST_SDA, LOW);
    delayMicroseconds(5);
    digitalWrite(WRIST_SCL, HIGH);
    delayMicroseconds(5);
    digitalWrite(WRIST_SDA, HIGH);
    delayMicroseconds(5);
}

bool i2c_write_byte(uint8_t data) {
    pinMode(WRIST_SDA, OUTPUT);
    for (int i = 7; i >= 0; i--) {
        digitalWrite(WRIST_SDA, (data >> i) & 0x01);
        delayMicroseconds(5);
        digitalWrite(WRIST_SCL, HIGH);
        delayMicroseconds(5);
        digitalWrite(WRIST_SCL, LOW);
    }
    
    // check ACK
    pinMode(WRIST_SDA, INPUT_PULLUP);
    delayMicroseconds(5);
    digitalWrite(WRIST_SCL, HIGH);
    delayMicroseconds(5);
    bool ack = digitalRead(WRIST_SDA) == LOW;
    digitalWrite(WRIST_SCL, LOW);
    return ack;
}

uint8_t i2c_read_byte(bool ack) {
    uint8_t data = 0;
    pinMode(WRIST_SDA, INPUT_PULLUP);
    
    for (int i = 7; i >= 0; i--) {
        digitalWrite(WRIST_SCL, HIGH);
        delayMicroseconds(5);
        if (digitalRead(WRIST_SDA)) data |= (1 << i);
        digitalWrite(WRIST_SCL, LOW);
        delayMicroseconds(5);
    }
    
    // send ACK/NACK
    pinMode(WRIST_SDA, OUTPUT);
    digitalWrite(WRIST_SDA, ack ? LOW : HIGH);
    delayMicroseconds(5);
    digitalWrite(WRIST_SCL, HIGH);
    delayMicroseconds(5);
    digitalWrite(WRIST_SCL, LOW);
    
    return data;
}

uint8_t read_wrist_axis(uint8_t reg) {
    i2c_start();
    if (!i2c_write_byte((MMA7660_ADDR << 1) | 0)) { // write address
        i2c_stop();
        return 0;
    }
    if (!i2c_write_byte(reg)) { // register address
        i2c_stop();
        return 0;
    }
    
    i2c_start(); // repeated start
    if (!i2c_write_byte((MMA7660_ADDR << 1) | 1)) { // read
        i2c_stop();
        return 0;
    }
    uint8_t data = i2c_read_byte(false); // NACK on last byte
    i2c_stop();
    
    return data;
}

void update_wrist() {
    uint8_t ax_raw = read_wrist_axis(0x00);
    uint8_t ay_raw = read_wrist_axis(0x01);
    uint8_t az_raw = read_wrist_axis(0x02);
    
    // convert to signed
    uint8_t ax_val = ax_raw & 0x3F;
    uint8_t ay_val = ay_raw & 0x3F;
    uint8_t az_val = az_raw & 0x3F;
    
    int8_t ax = ax_val > 31 ? ax_val - 64 : ax_val;
    int8_t ay = ay_val > 31 ? ay_val - 64 : ay_val;
    int8_t az = az_val > 31 ? az_val - 64 : az_val;
    
    // calculate angles (pitch + roll)
    float raw_pitch = atan2(-(float)ax, sqrt((float)ay*ay + (float)az*az)) * (180.0 / PI);
    float raw_roll = atan2((float)ay, (float)az) * (180.0 / PI);
    
    wrist_pitch = (ALPHA * raw_pitch) + ((1.0 - ALPHA) * wrist_pitch);
    wrist_roll = (ALPHA * raw_roll) + ((1.0 - ALPHA) * wrist_roll);
}

void init_wrist() {
    pinMode(WRIST_SDA, OUTPUT);
    pinMode(WRIST_SCL, OUTPUT);
    digitalWrite(WRIST_SDA, HIGH);
    digitalWrite(WRIST_SCL, HIGH);
    delay(10);
    
    // initialize sensor
    i2c_start();
    i2c_write_byte((MMA7660_ADDR << 1) | 0);
    i2c_write_byte(0x07); // MODE register
    i2c_write_byte(0x01); // active mode
    i2c_stop();
}

unsigned long lastUpdate = 0;
const int UPDATE_INTERVAL_MS = 50;

void setup() {
    Serial.begin(115200);
    delay(2000);
    
    Serial.println("\n=== Dual IMU (HW I2C + Bit-Bang) ===");
    
    // bicep: hardware I2C
    Serial.print("Bicep IMU (Hardware I2C): ");
    bicepIMU.begin(5, 6);
    Serial.println("✓");
    
    // wrist: bit-banged I2C
    Serial.print("Wrist IMU (Bit-Bang I2C): ");
    init_wrist();
    Serial.println("✓");
    
    Serial.println("\nStarting data stream...\n");
}

void loop() {
    if (millis() - lastUpdate >= UPDATE_INTERVAL_MS) {
        lastUpdate = millis();
        
        bicepIMU.update();
        update_wrist();
        
        String payload = String(bicepIMU.getPitch(), 1) + "," + 
                         String(bicepIMU.getRoll(), 1) + "," +
                         String(wrist_pitch, 1) + "," + 
                         String(wrist_roll, 1);
        
        Serial.println(payload);
    }
}