#include <Arduino.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

#include "../include/imu/mpu6050_filter.hpp"
#include "../include/bluetooth/ble_manager.hpp"

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

// both sensors use hardware i2c
MPU6050Filter bicepIMU(&Wire, 0x69, 0.10); // AD0 tied to GND
MPU6050Filter wristIMU(&Wire, 0x68, 0.10);

unsigned long lastUpdate = 0;
const int UPDATE_INTERVAL_MS = 12; // 80Hz

void setup() {
    Serial.begin(115200);
    delay(2000);
    
    Serial.println("\n=== Dual IMU (Shared Hardware I2C Bus) ===");
    
    // start the I2C bus ocnce  on pins 5 and 6
    Wire.begin(5, 6);
    
    // initialize screen
    Serial.print("Initializing OLED Screen: ");
    if(!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
        Serial.println("FAILED");
    } else {
        Serial.println("✓");
        display.clearDisplay();
        display.setTextSize(2); 
        display.setTextColor(SSD1306_WHITE);
        display.setCursor(10, 20); 
        display.println("^_^");
        display.display();
    }
    
    // Initialize Sensors (They don't need begin(5,6) anymore since Wire is already started)
    Serial.print("Initializing Bicep IMU (0x68)... ");
    bicepIMU.begin(5, 6); 
    Serial.println("✓");

    Serial.print("Initializing Wrist IMU (0x69)... ");
    wristIMU.begin(5, 6); 
    Serial.println("✓");

    // Init Bluetooth
    Serial.println("Initializing BLE...");

    init_BLE();
    
    Serial.println("\nStarting data stream...\n");
}

void loop() {
    if (millis() - lastUpdate >= UPDATE_INTERVAL_MS) {
        lastUpdate = millis();
        
        bicepIMU.update();
        wristIMU.update();

        // pack data
        currentData.timestamp_ms = millis();
        
        currentData.bicep_pitch = bicepIMU.getPitch();
        currentData.bicep_roll = bicepIMU.getRoll();
        currentData.bicep_yaw = bicepIMU.getYaw();
        
        currentData.wrist_pitch = wristIMU.getPitch(); 
        currentData.wrist_roll = wristIMU.getRoll();
        currentData.wrist_yaw = wristIMU.getYaw(); 

        AxisData b_accel = bicepIMU.getAccel();
        currentData.bicep_accel_x = b_accel.x;
        currentData.bicep_accel_y = b_accel.y;
        currentData.bicep_accel_z = b_accel.z;
        
        AxisData b_gyro = bicepIMU.getGyro();
        currentData.bicep_gyro_x = b_gyro.x;
        currentData.bicep_gyro_y = b_gyro.y;
        currentData.bicep_gyro_z = b_gyro.z;

        // --- NEW: Pack Wrist Accel & Gyro ---
        AxisData w_accel = wristIMU.getAccel();
        currentData.wrist_accel_x = w_accel.x;
        currentData.wrist_accel_y = w_accel.y;
        currentData.wrist_accel_z = w_accel.z;
        
        AxisData w_gyro = wristIMU.getGyro();
        currentData.wrist_gyro_x = w_gyro.x;
        currentData.wrist_gyro_y = w_gyro.y;
        currentData.wrist_gyro_z = w_gyro.z;

        // UART
        Serial.printf("T:%lu | Bicep(P:%.1f, R:%.1f, Y:%.1f) | Wrist(P:%.1f, R:%.1f, Y:%.1f)\n", 
            currentData.timestamp_ms,
            currentData.bicep_pitch, currentData.bicep_roll, currentData.bicep_yaw,
            currentData.wrist_pitch, currentData.wrist_roll, currentData.wrist_yaw
        );

        notify_BLE();
    }
}