#include <Arduino.h>
#include "../include/imu_filter.hpp" 

MMA7660Filter bicepIMU(&Wire, 0.10);  
MMA7660Filter wristIMU(&Wire1, 0.10);

unsigned long lastUpdate = 0;
const int UPDATE_INTERVAL_MS = 50;

void setup() {
    Serial.begin(115200);
    delay(2000); 
    
    Serial.println("\n\n=== ESP32-C3 Dual IMU Test ===");
    Serial.println("USB CDC Connected!");
    
    // initialize IMUs with error handling
    Serial.println("\nInitializing sensors:");
    bool bicep_ok = bicepIMU.begin(5, 6);
    bool wrist_ok = wristIMU.begin(2, 3);
    
    Serial.println("\nSensor Status:");
    Serial.print("  Bicep IMU: ");
    Serial.println(bicep_ok ? "CONNECTED" : "NOT FOUND");
    Serial.print("  Wrist IMU: ");
    Serial.println(wrist_ok ? "CONNECTED" : "NOT FOUND");
    
    if (!bicep_ok && !wrist_ok) {
        Serial.println("\n⚠ WARNING: No IMUs detected!");
        Serial.println("Will send dummy data for testing.");
    }
    
    Serial.println("\nStarting data stream...");
    Serial.println("Format: bicep_pitch,bicep_roll,wrist_pitch,wrist_roll\n");
}

void loop() {
    if (millis() - lastUpdate >= UPDATE_INTERVAL_MS) {
        lastUpdate = millis();
        
        // update sensors (safe even if not connected)
        bicepIMU.update();
        wristIMU.update();
        
        // Format payload
        String payload = String(bicepIMU.getPitch(), 1) + "," + 
                         String(bicepIMU.getRoll(), 1) + "," +
                         String(wristIMU.getPitch(), 1) + "," + 
                         String(wristIMU.getRoll(), 1);
        
        Serial.println(payload);
    }
}
