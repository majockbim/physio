import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var bleManager = BLEManager()
    @StateObject private var repScorer = RepScorer()

    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack {
                DevicesView()
            }
            .tabItem {
                Label("Devices", systemImage: bleManager.connectionState == .connected
                      ? "antenna.radiowaves.left.and.right"
                      : "antenna.radiowaves.left.and.right.slash")
            }
        }
        .environmentObject(bleManager)
        .environmentObject(repScorer)
    }
}

private struct HomeView: View {
    @Query(sort: \SessionRecord.date, order: .reverse) private var sessions: [SessionRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stroke Rehab")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Personalized training to support recovery")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                NavigationLink {
                    ExerciseSelectionView()
                } label: {
                    Label("Start Session", systemImage: "play.circle.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.tint, in: .rect(cornerRadius: 14))
                        .foregroundStyle(.white)
                        .accessibilityHint("Begin today's guided training")
                }

                HStack(spacing: 12) {
                    NavigationLink {
                        Text("Exercises").navigationTitle("Exercises")
                    } label: {
                        Label("Exercises", systemImage: "figure.strengthtraining.traditional")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.15), in: .rect(cornerRadius: 14))
                    }

                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("Progress", systemImage: "chart.bar.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.15), in: .rect(cornerRadius: 14))
                    }
                }
            }

            recentSection

            Spacer()

            Text("Always consult your clinician for personalized guidance.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
        .navigationTitle("Home")
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.title2.bold())
            if sessions.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .imageScale(.large)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading) {
                        Text("No session started yet")
                            .font(.headline)
                        Text("When you begin, we'll track your time and reps here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 14))
            } else {
                VStack(spacing: 8) {
                    ForEach(sessions.prefix(3)) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            RecentSessionRow(session: session)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct RecentSessionRow: View {
    let session: SessionRecord

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.date.sessionLabel)
                    .font(.headline)
                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(session.compositeScore)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(session.compositeScore.scoreColor)
        }
        .padding()
        .background(Color.gray.opacity(0.12), in: .rect(cornerRadius: 14))
    }

    private var subtitleText: String {
        let exCount = session.exerciseResults.count
        let repCount = session.exerciseResults.reduce(0) { $0 + $1.repScores.count }
        return "\(exCount) exercise\(exCount == 1 ? "" : "s") · \(repCount) rep\(repCount == 1 ? "" : "s")"
    }

}


#Preview {
    ContentView()
}
