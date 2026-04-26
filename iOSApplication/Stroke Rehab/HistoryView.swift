import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \SessionRecord.date, order: .reverse) private var sessions: [SessionRecord]

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions Yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Complete a session to see your progress here.")
                )
            } else {
                List {
                    ForEach(sessions) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            SessionHistoryRow(session: session)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct SessionHistoryRow: View {
    let session: SessionRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.date.sessionLabel)
                    .font(.headline)
                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(session.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text("\(session.compositeScore)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(session.compositeScore.scoreColor)
        }
        .padding(.vertical, 2)
    }

    private var subtitleText: String {
        let exCount = session.exerciseResults.count
        let repCount = session.exerciseResults.reduce(0) { $0 + $1.repScores.count }
        return "\(exCount) exercise\(exCount == 1 ? "" : "s") · \(repCount) rep\(repCount == 1 ? "" : "s")"
    }
}
