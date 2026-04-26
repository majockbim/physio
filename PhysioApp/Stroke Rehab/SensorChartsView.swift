import SwiftUI
import Charts

struct SensorChartsView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var chartHistory: [BLEManager.TimedPayload] = []

    var body: some View {
        Group {
            chartSection(title: "Orientation",   samples: orientationSamples, yLabel: "°")
            chartSection(title: "Accelerometer", samples: accelSamples,       yLabel: "g")
            chartSection(title: "Gyroscope",     samples: gyroSamples,        yLabel: "°/s")
        }
        .onReceive(
            ble.$payloadHistory
                .throttle(for: .seconds(0.5), scheduler: RunLoop.main, latest: true)
        ) { chartHistory = $0 }
    }

    // MARK: - Chart sections

    private func chartSection(title: String, samples: [ChartSample], yLabel: String) -> some View {
        Section(title) {
            Chart(samples) { sample in
                LineMark(
                    x: .value("Time (s)", sample.time),
                    y: .value(yLabel,     sample.value)
                )
                .foregroundStyle(by: .value("Channel", sample.series))
            }
            .chartXAxisLabel("seconds")
            .chartYAxisLabel(yLabel)
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 180)
            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        }
    }

    // MARK: - Sample builders

    private var orientationSamples: [ChartSample] {
        chartHistory.flatMap { e in [
            ChartSample(time: e.time, value: Double(e.payload.bicep_pitch), series: "B Pitch"),
            ChartSample(time: e.time, value: Double(e.payload.bicep_roll),  series: "B Roll"),
            ChartSample(time: e.time, value: Double(e.payload.bicep_yaw),   series: "B Yaw"),
            ChartSample(time: e.time, value: Double(e.payload.wrist_pitch), series: "W Pitch"),
            ChartSample(time: e.time, value: Double(e.payload.wrist_roll),  series: "W Roll"),
            ChartSample(time: e.time, value: Double(e.payload.wrist_yaw),   series: "W Yaw"),
        ]}
    }

    private var accelSamples: [ChartSample] {
        chartHistory.flatMap { e in [
            ChartSample(time: e.time, value: Double(e.payload.bicep_accel_x), series: "B Accel X"),
            ChartSample(time: e.time, value: Double(e.payload.bicep_accel_y), series: "B Accel Y"),
            ChartSample(time: e.time, value: Double(e.payload.bicep_accel_z), series: "B Accel Z"),
            ChartSample(time: e.time, value: Double(e.payload.wrist_accel_x), series: "W Accel X"),
            ChartSample(time: e.time, value: Double(e.payload.wrist_accel_y), series: "W Accel Y"),
            ChartSample(time: e.time, value: Double(e.payload.wrist_accel_z), series: "W Accel Z"),
        ]}
    }

    private var gyroSamples: [ChartSample] {
        chartHistory.flatMap { e in [
            ChartSample(time: e.time, value: Double(e.payload.bicep_gyro_x), series: "B Gyro X"),
            ChartSample(time: e.time, value: Double(e.payload.bicep_gyro_y), series: "B Gyro Y"),
            ChartSample(time: e.time, value: Double(e.payload.bicep_gyro_z), series: "B Gyro Z"),
            ChartSample(time: e.time, value: Double(e.payload.wrist_gyro_x), series: "W Gyro X"),
            ChartSample(time: e.time, value: Double(e.payload.wrist_gyro_y), series: "W Gyro Y"),
            ChartSample(time: e.time, value: Double(e.payload.wrist_gyro_z), series: "W Gyro Z"),
        ]}
    }
}

// MARK: - Helpers

private struct ChartSample: Identifiable {
    var id: String { "\(series)@\(time)" }
    let time: Double
    let value: Double
    let series: String
}
