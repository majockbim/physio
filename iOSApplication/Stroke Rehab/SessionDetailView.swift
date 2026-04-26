import SwiftUI

struct SessionDetailView: View {
    let session: SessionRecord

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                scoreRing
                exerciseList
            }
            .padding()
        }
        .navigationTitle(session.date.detailTitle)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Composite ring

    private var scoreRing: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: CGFloat(session.compositeScore) / 100)
                    .stroke(session.compositeScore.scoreColor,
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(session.compositeScore)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(session.compositeScore.scoreColor)
            }
            .frame(width: 130, height: 130)
            Text("Session Score")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(session.date, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Exercise cards

    private var exerciseList: some View {
        VStack(spacing: 14) {
            ForEach(session.exerciseResults, id: \.exerciseId) { result in
                ExerciseResultCard(result: result)
            }
        }
    }

}

// MARK: - Per-exercise card

private struct ExerciseResultCard: View {
    let result: ExerciseResult

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: result.systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                Text(result.exerciseName)
                    .font(.headline)
                Spacer()
                if !result.repScores.isEmpty {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(result.averageScore)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(result.averageScore.scoreColor)
                        Text("avg")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, result.repScores.isEmpty ? 14 : 10)

            if !result.repScores.isEmpty {
                Divider()
                    .padding(.horizontal, 14)

                VStack(spacing: 0) {
                    ForEach(Array(result.repScores.enumerated()), id: \.offset) { index, score in
                        HStack {
                            Text("Rep \(index + 1)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(score)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(score.scoreColor)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)

                        if index < result.repScores.count - 1 {
                            Divider()
                                .padding(.horizontal, 14)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .background(Color.gray.opacity(0.12), in: .rect(cornerRadius: 14))
    }

}

private extension Date {
    var detailTitle: String {
        if Calendar.current.isDateInToday(self) { return "Today" }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
