import SwiftUI
import CoreBluetooth

struct DevicesView: View {
    @EnvironmentObject var ble: BLEManager

    var body: some View {
        Form {
            statusSection
            if ble.connectionState != .connected && (ble.connectionState == .scanning || !targetPeripherals.isEmpty) {
                discoverySection
            }
            if ble.connectionState == .connected {
                connectedSection
            }
        }
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if ble.connectionState == .idle {
                ble.startScanning()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    DeveloperView()
                } label: {
                    Image(systemName: "gear")
                }
            }
        }
    }

    private var targetPeripherals: [CBPeripheral] {
        ble.discoveredPeripherals.filter { ble.targetPeripheralIDs.contains($0.identifier) }
    }

    // MARK: - Status row

    private var statusSection: some View {
        Section {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 10, height: 10)
                Text(connectionLabel)
                    .font(.subheadline)
                Spacer()
                if ble.connectionState == .connected {
                    Button("Disconnect") { ble.disconnect() }
                } else if ble.connectionState == .idle || ble.connectionState == .scanning {
                    Button(ble.connectionState == .scanning ? "Stop" : "Scan") {
                        ble.connectionState == .scanning ? ble.stopScanning() : ble.startScanning()
                    }
                    .disabled(ble.connectionState == .unavailable)
                }
            }
        }
    }

    private var connectionLabel: String {
        switch ble.connectionState {
        case .connected:   return "Connected"
        case .connecting:  return "Connecting…"
        case .scanning:    return "Scanning…"
        case .idle:        return "Ready"
        case .unavailable: return "Bluetooth unavailable"
        }
    }

    // MARK: - Device discovery

    private var discoverySection: some View {
        Section("Nearby Devices") {
            if targetPeripherals.isEmpty {
                Label("Searching for sensor…", systemImage: "ellipsis")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(targetPeripherals, id: \.identifier) { peripheral in
                    Button {
                        ble.connect(to: peripheral)
                    } label: {
                        HStack {
                            Image(systemName: "sensor.fill")
                                .foregroundStyle(Color.accentColor)
                            Text(peripheral.name ?? peripheral.identifier.uuidString)
                            Spacer()
                            if ble.connectionState == .connecting {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Color.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: - Connected state

    private var connectedSection: some View {
        Section {
            NavigationLink {
                SensorDetailView()
                    .environmentObject(ble)
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ble.connectedPeripheralName ?? "Sensor")
                            .font(.headline)
                        Text("Tap to view sensor data")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

        }
    }

    private var statusDotColor: Color {
        switch ble.connectionState {
        case .connected:   return .green
        case .connecting:  return .orange
        case .scanning:    return .blue
        case .unavailable: return .red
        case .idle:        return Color.gray.opacity(0.5)
        }
    }
}

#Preview {
    NavigationStack {
        DevicesView()
            .environmentObject(BLEManager())
    }
}
