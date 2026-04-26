#include <Arduino.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

#include "../include/imu/mpu6050_filter.hpp"
#include "../include/bluetooth/ble_manager.hpp"

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

// Both sensors now use Hardware I2C! Just pass their specific addresses.
MPU6050Filter bicepIMU(&Wire, 0x68, 0.10); // AD0 tied to GND
MPU6050Filter wristIMU(&Wire, 0x69, 0.10); // AD0 tied to 3.3V

unsigned long lastUpdate = 0;
const int UPDATE_INTERVAL_MS = 12; // 80Hz

void setup() {
    Serial.begin(115200);
    delay(2000);
    
    Serial.println("\n=== Dual IMU (Shared Hardware I2C Bus) ===");
    
    // Start the I2C bus ONCE on pins 5 and 6
    Wire.begin(5, 6);
    
    // Initialize Screen (Address 0x3C)
    Serial.print("Initializing OLED Screen: ");
    if(!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
        Serial.println("FAILED");
    } else {
        Serial.println("✓");
        display.clearDisplay();
        display.setTextSize(2); 
        display.setTextColor(SSD1306_WHITE);
        display.setCursor(10, 20); 
        display.println("strokr");
        display.display();
    }
    
    // Initialize Sensors (They don't need begin(5,6) anymore since Wire is already started)
    Serial.print("Initializing Bicep IMU (0x68)... ");
    bicepIMU.begin(5, 6); 
    Serial.println("✓");

    Serial.print("Initializing Wrist IMU (0x69)... ");
    wristIMU.begin(5, 6); 
    Serial.println("✓");

    Serial.println("Initializing BLE...");
    init_BLE();

    Serial.println("\nStarting data stream...\n");
}

void loop() {
    if (millis() - lastUpdate >= UPDATE_INTERVAL_MS) {
        lastUpdate = millis();
        
        // Read both hardware sensors
        bicepIMU.update();
        wristIMU.update();

        // Pack data
        currentData.timestamp_ms = millis();
        currentData.bicep_pitch = bicepIMU.getPitch();
        currentData.bicep_roll = bicepIMU.getRoll();
        currentData.wrist_pitch = wristIMU.getPitch(); // Much cleaner!
        currentData.wrist_roll = wristIMU.getRoll();

        Serial.printf("T:%lu | Bicep(P:%.1f, R:%.1f) | Wrist(P:%.1f, R:%.1f)\n", 
            currentData.timestamp_ms,
            currentData.bicep_pitch, currentData.bicep_roll,
            currentData.wrist_pitch, currentData.wrist_roll
        );
        
        notify_BLE();
    }
}