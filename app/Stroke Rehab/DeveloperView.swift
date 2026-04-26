import SwiftUI

struct DeveloperView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var scorer: RepScorer

    var body: some View {
        Form {
            aboutSection
            developerSection
            modelSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .onReceive(
            ble.$payloadHistory
                .throttle(for: .seconds(2), scheduler: RunLoop.main, latest: true)
        ) { payloads in
            guard scorer.isModelLoaded else { return }
            scorer.run(payloads: payloads.map(\.payload))
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Stroke Rehab")
                    .font(.headline)
                Text("Movement quality tracking to support stroke recovery.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Developer

    private var developerSection: some View {
        Section("Developer") {
            Text(ble.statusMessage)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
            NavigationLink {
                LogOutputView()
            } label: {
                Label("Log Output", systemImage: "terminal")
            }
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        Section("Movement Quality Model") {
            if let progress = scorer.downloadProgress {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Downloading model…")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.system(.body, design: .monospaced))
                    }
                    ProgressView(value: progress)
                }
            }

            if let score = scorer.latestScore {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Movement Quality")
                            .font(.headline)
                        Text("Last 30 s · \(ble.payloadHistory.count) samples")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(score)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(score.scoreColor)
                }
                .padding(.vertical, 4)
            }

            if let err = scorer.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                scorer.run(payloads: ble.payloadHistory.map(\.payload))
            } label: {
                if scorer.isRunning {
                    Label("Running…", systemImage: "hourglass")
                } else if ble.connectionState != .connected {
                    Label("No Device Connected", systemImage: "antenna.radiowaves.left.and.right.slash")
                } else {
                    Label("Run Model", systemImage: "brain")
                }
            }
            .disabled(scorer.isRunning || ble.connectionState != .connected || ble.payloadHistory.count < 2)
        }
    }

}

#Preview {
    NavigationStack {
        DeveloperView()
            .environmentObject(BLEManager())
            .environmentObject(RepScorer())
    }
}
