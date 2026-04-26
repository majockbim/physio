#include "../include/bluetooth/ble_manager.hpp"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// global vars
SensorPayload currentData;
bool deviceConnected = false;

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;

// custom UUIDs for app -> target
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        deviceConnected = true;
        Serial.println(">>> Swift App Connected via BLE <<<");
    };

    void onDisconnect(BLEServer* pServer) {
        deviceConnected = false;
        Serial.println(">>> Swift App Disconnected. Restarting broadcast... <<<");
        BLEDevice::startAdvertising(); 
    }
};

void init_BLE() {
    BLEDevice::init("ESP32_Arm_Tracker");
    BLEDevice::setMTU(512); // for the addition of the 12 extra gyro/accel floats later

    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());

    BLEService *pService = pServer->createService(SERVICE_UUID);

    pCharacteristic = pService->createCharacteristic(
                        CHARACTERISTIC_UUID,
                        BLECharacteristic::PROPERTY_NOTIFY
                      );

    // required so iOS knows it can subscribe to this data stream
    pCharacteristic->addDescriptor(new BLE2902());

    pService->start();

    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    
    // helps iOS discover the device faster
    pAdvertising->setMinPreferred(0x06);  
    pAdvertising->setMinPreferred(0x12);
    
    BLEDevice::startAdvertising();
    Serial.println("BLE Initialized. Broadcasting as 'ESP32_Arm_Tracker'...");
}

void notify_BLE() {
    if (deviceConnected && pCharacteristic != NULL) {
        pCharacteristic->setValue((uint8_t*)&currentData, sizeof(SensorPayload));
        pCharacteristic->notify();
    }
}