import SwiftUI

struct SensorDetailView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var displayed: SensorPayload? = nil

    var body: some View {
        Form {
            Section("Live Data") {
                if let p = displayed {
                    SensorRow(label: "Timestamp",     value: "\(p.timestamp_ms) ms")

                    SensorRow(label: "Bicep Pitch",   value: String(format: "%.2f°", p.bicep_pitch))
                    SensorRow(label: "Bicep Roll",    value: String(format: "%.2f°", p.bicep_roll))
                    SensorRow(label: "Bicep Yaw",     value: String(format: "%.2f°", p.bicep_yaw))
                    SensorRow(label: "Wrist Pitch",   value: String(format: "%.2f°", p.wrist_pitch))
                    SensorRow(label: "Wrist Roll",    value: String(format: "%.2f°", p.wrist_roll))
                    SensorRow(label: "Wrist Yaw",     value: String(format: "%.2f°", p.wrist_yaw))

                    SensorRow(label: "Bicep Accel X", value: String(format: "%.3f g", p.bicep_accel_x))
                    SensorRow(label: "Bicep Accel Y", value: String(format: "%.3f g", p.bicep_accel_y))
                    SensorRow(label: "Bicep Accel Z", value: String(format: "%.3f g", p.bicep_accel_z))
                    SensorRow(label: "Bicep Gyro X",  value: String(format: "%.3f °/s", p.bicep_gyro_x))
                    SensorRow(label: "Bicep Gyro Y",  value: String(format: "%.3f °/s", p.bicep_gyro_y))
                    SensorRow(label: "Bicep Gyro Z",  value: String(format: "%.3f °/s", p.bicep_gyro_z))

                    SensorRow(label: "Wrist Accel X", value: String(format: "%.3f g", p.wrist_accel_x))
                    SensorRow(label: "Wrist Accel Y", value: String(format: "%.3f g", p.wrist_accel_y))
                    SensorRow(label: "Wrist Accel Z", value: String(format: "%.3f g", p.wrist_accel_z))
                    SensorRow(label: "Wrist Gyro X",  value: String(format: "%.3f °/s", p.wrist_gyro_x))
                    SensorRow(label: "Wrist Gyro Y",  value: String(format: "%.3f °/s", p.wrist_gyro_y))
                    SensorRow(label: "Wrist Gyro Z",  value: String(format: "%.3f °/s", p.wrist_gyro_z))
                } else {
                    Label("Waiting for packets…", systemImage: "waveform")
                        .foregroundStyle(.secondary)
                }
            }

            if !ble.payloadHistory.isEmpty {
                SensorChartsView()
            }
        }
        .navigationTitle(ble.connectedPeripheralName ?? "Sensor")
        .navigationBarTitleDisplayMode(.large)
        .onReceive(
            ble.$latestPayload
                .throttle(for: .seconds(0.5), scheduler: RunLoop.main, latest: true)
        ) { displayed = $0 }
    }
}

// MARK: - Helpers

struct SensorRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.system(.body, design: .monospaced))
        }
    }
}

#Preview {
    NavigationStack {
        SensorDetailView()
            .environmentObject(BLEManager())
    }
}
