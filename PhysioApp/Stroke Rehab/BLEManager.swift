import CoreBluetooth
import Foundation

// Mirror of the C++ ESP32 struct — must match byte-for-byte (76 bytes, dual MPU6050 + yaw)
struct SensorPayload {
    var timestamp_ms: UInt32

    var bicep_pitch:   Float32
    var bicep_roll:    Float32
    var bicep_yaw:     Float32
    var wrist_pitch:   Float32
    var wrist_roll:    Float32
    var wrist_yaw:     Float32

    var bicep_accel_x: Float32
    var bicep_accel_y: Float32
    var bicep_accel_z: Float32
    var bicep_gyro_x:  Float32
    var bicep_gyro_y:  Float32
    var bicep_gyro_z:  Float32

    var wrist_accel_x: Float32
    var wrist_accel_y: Float32
    var wrist_accel_z: Float32
    var wrist_gyro_x:  Float32
    var wrist_gyro_y:  Float32
    var wrist_gyro_z:  Float32
}

final class BLEManager: NSObject, ObservableObject {

    static let serviceUUID        = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    static let characteristicUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")

    enum ConnectionState: Equatable {
        case unavailable
        case idle
        case scanning
        case connecting
        case connected
    }

    struct TimedPayload: Identifiable {
        let id = UUID()
        let time: Double   // seconds since first packet this session
        let payload: SensorPayload
    }

    @Published var connectionState: ConnectionState = .idle
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var targetPeripheralIDs: Set<UUID> = []
    @Published var connectedPeripheralName: String? = nil
    @Published var latestPayload: SensorPayload? = nil
    @Published var payloadHistory: [TimedPayload] = []
    @Published var statusMessage: String = "Initializing…"

    @Published var sessionStartDate: Date? = nil
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var peripheralMap: [UUID: CBPeripheral] = [:]

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            appLog("Cannot scan — Bluetooth state: \(centralManager.state.rawValue)", level: .warning)
            return
        }
        peripheralMap.removeAll()
        targetPeripheralIDs.removeAll()
        discoveredPeripherals = []
        connectionState = .scanning
        statusMessage = "Scanning for all devices…"
        // Scan for ALL peripherals (nil services) so we can see everything in the area,
        // including devices that might not be advertising the expected service UUID.
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        appLog("Scan started — listening for all nearby peripherals", level: .info)
        appLog("Target service UUID:        \(Self.serviceUUID.uuidString)", level: .debug)
        appLog("Target characteristic UUID: \(Self.characteristicUUID.uuidString)", level: .debug)
    }

    func stopScanning() {
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = .idle
            statusMessage = "Scan stopped."
            appLog("Scan stopped. \(peripheralMap.count) device(s) found.", level: .info)
        }
    }

    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectionState = .connecting
        statusMessage = "Connecting to \(peripheral.name ?? "device")…"
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        appLog("Initiating connection to: \(peripheral.name ?? "(unnamed)") [\(peripheral.identifier)]", level: .info)
    }

    func disconnect() {
        guard let p = connectedPeripheral else { return }
        appLog("Disconnecting from \(p.name ?? "(unnamed)")", level: .info)
        centralManager.cancelPeripheralConnection(p)
    }

    private func resetConnection() {
        if let p = connectedPeripheral {
            peripheralMap.removeValue(forKey: p.identifier)
            targetPeripheralIDs.remove(p.identifier)
            discoveredPeripherals = Array(peripheralMap.values)
                .sorted { a, b in
                    let aTarget = targetPeripheralIDs.contains(a.identifier)
                    let bTarget = targetPeripheralIDs.contains(b.identifier)
                    if aTarget != bTarget { return aTarget }
                    return (a.name ?? "") < (b.name ?? "")
                }
        }
        connectedPeripheral = nil
        connectedPeripheralName = nil
        latestPayload = nil
        payloadHistory = []
        sessionStartDate = nil
        connectionState = centralManager.state == .poweredOn ? .idle : .unavailable
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let stateLabel: String
        switch central.state {
        case .poweredOn:      stateLabel = "poweredOn"
        case .poweredOff:     stateLabel = "poweredOff"
        case .unauthorized:   stateLabel = "unauthorized"
        case .unsupported:    stateLabel = "unsupported"
        case .resetting:      stateLabel = "resetting"
        case .unknown:        stateLabel = "unknown"
        @unknown default:     stateLabel = "unknown(\(central.state.rawValue))"
        }
        appLog("CBCentralManager state → \(stateLabel)", level: .info)

        switch central.state {
        case .poweredOn:
            connectionState = .idle
            statusMessage = "Bluetooth ready."
        case .poweredOff:
            connectionState = .unavailable
            statusMessage = "Bluetooth is turned off."
            resetConnection()
        case .unauthorized:
            connectionState = .unavailable
            statusMessage = "Bluetooth permission denied. Check Settings."
        case .unsupported:
            connectionState = .unavailable
            statusMessage = "Bluetooth LE not supported on this device."
        default:
            connectionState = .unavailable
            statusMessage = "Bluetooth unavailable."
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "(unnamed)"
        let isNew = peripheralMap[peripheral.identifier] == nil

        // Parse advertisement data for logging
        let advServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .map(\.uuidString) ?? []
        let isTarget = advServices.contains { $0.caseInsensitiveCompare(Self.serviceUUID.uuidString) == .orderedSame }
        let txPower  = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? Int
        let isConnectable = advertisementData[CBAdvertisementDataIsConnectable] as? Bool

        if isNew {
            var parts = ["\(isTarget ? "★ TARGET" : "  ") \(name) [\(peripheral.identifier.uuidString.prefix(8))…]"]
            parts.append("RSSI: \(RSSI) dBm")
            if let tx = txPower { parts.append("TX: \(tx) dBm") }
            if let c = isConnectable { parts.append(c ? "connectable" : "not connectable") }
            if advServices.isEmpty {
                parts.append("services: (none advertised)")
            } else {
                parts.append("services: \(advServices.joined(separator: ", "))")
            }
            appLog(parts.joined(separator: " | "), level: isTarget ? .info : .debug)

            peripheralMap[peripheral.identifier] = peripheral
            if isTarget { targetPeripheralIDs.insert(peripheral.identifier) }
            discoveredPeripherals = Array(peripheralMap.values)
                .sorted { a, b in
                    let aTarget = targetPeripheralIDs.contains(a.identifier)
                    let bTarget = targetPeripheralIDs.contains(b.identifier)
                    if aTarget != bTarget { return aTarget }
                    return (a.name ?? "") < (b.name ?? "")
                }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected
        connectedPeripheralName = peripheral.name
        statusMessage = "Connected. Discovering services…"
        appLog("Connected to: \(peripheral.name ?? "(unnamed)") [\(peripheral.identifier)]", level: .info)
        appLog("Requesting service discovery (all services)…", level: .debug)
        // Discover ALL services so we can see what the device actually exposes
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error {
            appLog("Disconnected with error: \(error.localizedDescription)", level: .error)
            statusMessage = "Disconnected with error: \(error.localizedDescription)"
        } else {
            appLog("Disconnected cleanly from \(peripheral.name ?? "(unnamed)")", level: .info)
            statusMessage = "Disconnected."
        }
        resetConnection()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let msg = error?.localizedDescription ?? "unknown error"
        appLog("Failed to connect: \(msg)", level: .error)
        statusMessage = "Failed to connect: \(msg)"
        resetConnection()
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            appLog("Service discovery error: \(error.localizedDescription)", level: .error)
            statusMessage = "Service discovery failed."
            return
        }
        let services = peripheral.services ?? []
        appLog("Services found on device (\(services.count) total):", level: .info)
        for service in services {
            let isTarget = service.uuid == Self.serviceUUID
            appLog("  \(isTarget ? "★ TARGET" : " ") \(service.uuid.uuidString) (primary: \(service.isPrimary))", level: isTarget ? .info : .debug)
        }
        guard let target = services.first(where: { $0.uuid == Self.serviceUUID }) else {
            appLog("Target service \(Self.serviceUUID.uuidString) NOT found — is the ESP32 advertising the right UUID?", level: .warning)
            statusMessage = "Target service not found on device."
            return
        }
        appLog("Target service found — discovering all characteristics…", level: .info)
        peripheral.discoverCharacteristics(nil, for: target)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            appLog("Characteristic discovery error: \(error.localizedDescription)", level: .error)
            statusMessage = "Characteristic discovery failed."
            return
        }
        let chars = service.characteristics ?? []
        appLog("Characteristics found in service \(service.uuid.uuidString) (\(chars.count) total):", level: .info)
        for c in chars {
            let isTarget = c.uuid == Self.characteristicUUID
            let props = characteristicProperties(c.properties)
            appLog("  \(isTarget ? "★ TARGET" : " ") \(c.uuid.uuidString) [\(props)]", level: isTarget ? .info : .debug)
        }
        guard let target = chars.first(where: { $0.uuid == Self.characteristicUUID }) else {
            appLog("Target characteristic \(Self.characteristicUUID.uuidString) NOT found", level: .warning)
            statusMessage = "Target characteristic not found."
            return
        }
        guard target.properties.contains(.notify) || target.properties.contains(.indicate) else {
            appLog("Target characteristic does not support notify/indicate — cannot subscribe", level: .warning)
            return
        }
        peripheral.setNotifyValue(true, for: target)
        appLog("Subscribed to notifications on target characteristic", level: .info)
        statusMessage = "Subscribed — waiting for data…"
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appLog("didUpdateValue error: \(error.localizedDescription)", level: .error)
            statusMessage = "Data error: \(error.localizedDescription)"
            return
        }
        guard let data = characteristic.value else {
            appLog("Received notification but value is nil", level: .warning)
            return
        }
        let expectedSize = MemoryLayout<SensorPayload>.size
        appLog("Packet received — \(data.count)B (expected \(expectedSize)B) | hex: \(data.hexString)", level: .data)

        guard data.count == expectedSize else {
            appLog("Packet size mismatch — skipping decode", level: .warning)
            statusMessage = "Packet size mismatch — expected \(expectedSize)B, got \(data.count)B."
            return
        }
        var payload = SensorPayload(timestamp_ms: 0,
                                    bicep_pitch: 0, bicep_roll: 0, bicep_yaw: 0,
                                    wrist_pitch: 0, wrist_roll: 0, wrist_yaw: 0,
                                    bicep_accel_x: 0, bicep_accel_y: 0, bicep_accel_z: 0,
                                    bicep_gyro_x: 0, bicep_gyro_y: 0, bicep_gyro_z: 0,
                                    wrist_accel_x: 0, wrist_accel_y: 0, wrist_accel_z: 0,
                                    wrist_gyro_x: 0, wrist_gyro_y: 0, wrist_gyro_z: 0)
        withUnsafeMutableBytes(of: &payload) { data.copyBytes(to: $0) }
        latestPayload = payload
        statusMessage = "Receiving data."

        let now = Date()
        if sessionStartDate == nil { sessionStartDate = now }
        let t = now.timeIntervalSince(sessionStartDate!)
        payloadHistory.append(TimedPayload(time: t, payload: payload))
        let cutoff = t - 30.0
        payloadHistory.removeAll { $0.time < cutoff }
        appLog(String(format: "t=%ums  bicep(p=%.2f r=%.2f)  wrist(p=%.2f r=%.2f)",
                      payload.timestamp_ms,
                      payload.bicep_pitch, payload.bicep_roll,
                      payload.wrist_pitch, payload.wrist_roll), level: .data)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appLog("Notification state error: \(error.localizedDescription)", level: .error)
            return
        }
        appLog("Notification state for \(characteristic.uuid): \(characteristic.isNotifying ? "ON" : "OFF")", level: .info)
    }

    // MARK: - Helpers

    private func characteristicProperties(_ props: CBCharacteristicProperties) -> String {
        var parts: [String] = []
        if props.contains(.broadcast)                 { parts.append("broadcast") }
        if props.contains(.read)                      { parts.append("read") }
        if props.contains(.writeWithoutResponse)      { parts.append("writeNoRsp") }
        if props.contains(.write)                     { parts.append("write") }
        if props.contains(.notify)                    { parts.append("notify") }
        if props.contains(.indicate)                  { parts.append("indicate") }
        if props.contains(.authenticatedSignedWrites) { parts.append("signedWrite") }
        return parts.isEmpty ? "none" : parts.joined(separator: "|")
    }
}

// MARK: - Data hex helper

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
