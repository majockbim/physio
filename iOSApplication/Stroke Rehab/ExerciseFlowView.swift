import SwiftUI
import SwiftData
import UIKit

struct Exercise: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let description: String
    let systemImage: String
    let category: Category

    enum Category { case rom, adl }

    static let catalog: [Exercise] = romExercises + adlExercises

    static let romExercises: [Exercise] = [
        Exercise(id: "elbow-flexion",
                 name: "Elbow Flexion",
                 subtitle: "Bend and straighten your elbow",
                 description: "Start with your arm straight at your side. Bend your elbow to bring your hand up toward your shoulder, then lower it back down slowly.",
                 systemImage: "hand.point.up.left.fill",
                 category: .rom),
        Exercise(id: "shoulder-flexion-90",
                 name: "Shoulder Flexion to 90°",
                 subtitle: "Raise your arm to shoulder height",
                 description: "Stand or sit with your arm at your side. Raise your arm straight in front of you to shoulder height (90°), then lower it back down in a controlled movement.",
                 systemImage: "figure.walk",
                 category: .rom),
        Exercise(id: "shoulder-horiz-adduction",
                 name: "Shoulder Horizontal Adduction",
                 subtitle: "Bring your arm across your body",
                 description: "Hold your affected arm out to the side at shoulder height. Slowly bring it across your body toward the opposite shoulder, then return.",
                 systemImage: "arrow.left.and.right.circle",
                 category: .rom),
        Exercise(id: "forearm-sup-pro",
                 name: "Forearm Supination/Pronation",
                 subtitle: "Rotate your forearm palm-up and palm-down",
                 description: "With your elbow bent at 90°, rotate your forearm to turn your palm up (supination), then down (pronation). Keep your elbow close to your side.",
                 systemImage: "hand.raised.fill",
                 category: .rom),
    ]

    static let adlExercises: [Exercise] = [
        Exercise(id: "take-pill",
                 name: "Take a Pill",
                 subtitle: "Practice fine motor grasping and reaching",
                 description: "Practice the fine motor sequence of opening a pill bottle, picking up a small object, and bringing it to your mouth.",
                 systemImage: "pill.fill",
                 category: .adl),
        Exercise(id: "pour-water",
                 name: "Pour Water",
                 subtitle: "Grip, tilt, and return a cup",
                 description: "Practice grasping a cup or small pitcher, tipping it to pour, and returning it upright.",
                 systemImage: "drop.fill",
                 category: .adl),
        Exercise(id: "brush-teeth",
                 name: "Brush Teeth",
                 subtitle: "Simulate toothbrushing strokes",
                 description: "Simulate the motion of brushing teeth — grip the toothbrush, raise it to your mouth, and perform repeated side-to-side strokes.",
                 systemImage: "mouth.fill",
                 category: .adl),
    ]
}

struct ExerciseFlowView: View {
    // MARK: - Data
    private let exercises: [Exercise]

    // MARK: - Flow State
    @State private var currentExerciseIndex: Int = 0
    @State private var slide: Slide = .intro
    @State private var repState: RepState = .idle
    @State private var lastScore: Int? = nil
    @State private var lastFeedback: String = ""
    @State private var attemptResults: [[Int]]
    @State private var repStartTime: Double = 0
    @State private var repStartDate: Date? = nil
    @State private var liveScore: Int? = nil
    @State private var isLiveScoring = false
    @StateObject private var speech = SpeechManager()

    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var scorer: RepScorer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum RepState { case idle, recording, scoring }

    init(exercises: [Exercise]) {
        self.exercises = exercises
        _attemptResults = State(initialValue: Array(repeating: [], count: exercises.count))
    }

    private var currentExercise: Exercise { exercises[currentExerciseIndex] }
    private var totalExercises: Int { exercises.count }

    enum Slide: Equatable { case intro, perform, result, summary }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            content
            Spacer()
        }
        .padding()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .task(id: slide) {
            await speech.speak(speechText)
        }
        .onDisappear {
            speech.stop()
        }
        .onReceive(ble.$payloadHistory.throttle(for: .seconds(2), scheduler: RunLoop.main, latest: true)) { payloads in
            guard repState == .recording,
                  !isLiveScoring,
                  let startDate = repStartDate,
                  Date().timeIntervalSince(startDate) >= 3 else { return }
            let cutoff = repStartTime
            let repPayloads = payloads.filter { $0.time > cutoff }.map(\.payload)
            let scoringPayloads = repPayloads.count >= 2 ? repPayloads : payloads.map(\.payload)
            guard scoringPayloads.count >= 2 else { return }
            isLiveScoring = true
            Task { @MainActor in
                liveScore = await scorer.scoreRep(payloads: scoringPayloads)
                isLiveScoring = false
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if slide == .perform {
                Text("Do as many reps as you'd like, then move on when ready.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            switch slide {
            case .intro:
                Button { slide = .perform } label: {
                    Label("Begin Exercise", systemImage: "play.circle.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor, in: .rect(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
            case .perform:
                Button {
                    if repState == .idle { startAttempt() }
                    else if repState == .recording { finishAttempt() }
                } label: {
                    Label(
                        repState == .scoring ? "Scoring…" : repState == .recording ? "Finish Rep" : "Start Rep",
                        systemImage: repState == .scoring ? "hourglass" : repState == .recording ? "stop.circle.fill" : "figure.run"
                    )
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        repState == .scoring ? Color.gray.opacity(0.25) : repState == .recording ? Color.red.opacity(0.85) : Color.accentColor,
                        in: .rect(cornerRadius: 14)
                    )
                    .foregroundStyle(repState == .scoring ? Color.primary : Color.white)
                }
                .disabled(repState == .scoring)
            case .result:
                Button { slide = .perform } label: {
                    Label("Another Rep", systemImage: "arrow.counterclockwise")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor, in: .rect(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                Button { advanceToNextExercise() } label: {
                    Label(
                        currentExerciseIndex < totalExercises - 1 ? "Next Exercise" : "Finish Session",
                        systemImage: currentExerciseIndex < totalExercises - 1 ? "arrow.right" : "checkmark"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.15), in: .rect(cornerRadius: 14))
                    .foregroundStyle(.primary)
                }
            case .summary:
                Button { saveSession(); dismiss() } label: {
                    Label("Finish", systemImage: "checkmark")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor, in: .rect(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Speech

    private var speechText: String {
        switch slide {
        case .intro:
            let prefix = Self.introPrefixes.randomElement()!
            return "\(prefix)\(currentExercise.name). \(currentExercise.description)"
        case .perform:
            return Self.performPhrases.randomElement()!
        case .result:
            let score = lastScore ?? 0
            return "\(lastFeedback) You scored \(score)."
        case .summary:
            return Self.summaryPhrases.randomElement()!
        }
    }

    private func repFeedback(_ score: Int) -> String {
        switch score {
        case 80...: return Self.resultHighPhrases.randomElement()!
        case 60..<80: return Self.resultMidPhrases.randomElement()!
        default: return Self.resultLowPhrases.randomElement()!
        }
    }

    private static let introPrefixes = [
        "", "Up next: ", "Time for ", "Next exercise: ",
        "Let's work on ", "Now we'll do ", "Moving on to ",
        "Here's ", "Your next exercise is ", "Let's begin ", "Ready for ",
    ]

    private static let performPhrases = [
        "When you're ready, tap Start. We'll record your movement.",
        "Take your time, and tap Start when you're ready.",
        "Get into position and tap Start to begin.",
        "Tap Start whenever you feel ready.",
        "Whenever you're set, go ahead and tap Start.",
        "Tap Start and we'll measure your movement.",
        "Take a breath, get ready, and tap Start.",
        "Go ahead whenever you're ready.",
        "Tap Start when you feel ready.",
        "Nice work. Tap Start when you're ready for the next rep.",
        "You've got this. Tap Start to continue.",
    ]

    private static let resultHighPhrases = [
        "Excellent form!", "Great movement!", "Well done!",
        "Fantastic rep!", "That looked really solid!", "Perfect form on that one.",
        "Nicely done!", "That's a great rep.", "Outstanding!",
    ]

    private static let resultMidPhrases = [
        "Good effort.", "Nice work.", "Keep it up.",
        "That was solid.", "Good rep.", "You're doing well.",
        "Nice movement.", "Good form.", "Well done.",
    ]

    private static let resultLowPhrases = [
        "Every rep is progress.", "That rep is part of your recovery.",
        "Great effort on that one.", "You showed up and did the work.",
        "Recovery is built one rep at a time.", "That took real effort — well done.",
        "Each rep matters. Good work.", "You're doing the work. That counts.",
        "That rep is a step forward.",
    ]

    private static let summaryPhrases = [
        "Session complete. Great work today.",
        "You've finished the session. Excellent effort.",
        "That's a wrap! Great job today.",
        "Session done. You should be proud of yourself.",
        "All done! You worked hard today.",
        "Session complete. Well done.",
        "Great session today. Every rep counts.",
        "That's all for today. Fantastic work.",
        "You've completed your session. Wonderful effort.",
        "Session finished. Great job today.",
        "All exercises complete. You did great.",
    ]

    // MARK: - Sections
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if slide != .summary {
                Text(currentExercise.name)
                    .font(.title.bold())
                Text("Exercise \(currentExerciseIndex + 1) of \(totalExercises)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Session Summary")
                    .font(.title.bold())
                Text("Great work today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            if slide == .intro {
                introSlide
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
            if slide == .perform {
                performSlide
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
            if slide == .result {
                resultSlide
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
            if slide == .summary {
                summarySlide
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: slide)
    }

    private var introSlide: some View {
        HStack(spacing: 16) {
            Image(systemName: currentExercise.systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text(currentExercise.description)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.12), in: .rect(cornerRadius: 14))
    }

    private var liveScoreRing: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: CGFloat(liveScore ?? 0) / 100)
                    .stroke(
                        liveScore.map { $0.scoreColor } ?? Color.clear,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: liveScore)
                Group {
                    if let score = liveScore {
                        Text("\(score)")
                            .foregroundStyle(score.scoreColor)
                            .contentTransition(.numericText())
                    } else {
                        Text("—")
                            .foregroundStyle(Color.gray.opacity(0.35))
                    }
                }
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .animation(.easeInOut(duration: 0.3), value: liveScore != nil)
            }
            .frame(width: 160, height: 160)
            Text(liveScore == nil ? "Measuring…" : "Live Score")
                .font(.caption)
                .foregroundStyle(.secondary)
                .animation(.easeInOut(duration: 0.3), value: liveScore != nil)
        }
        .frame(maxWidth: .infinity)
        .opacity(repState == .idle ? 0.3 : 1)
        .animation(.easeInOut(duration: 0.25), value: repState == .idle)
    }

    private var performSlide: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(repState == .recording
                     ? "Performing rep. Tap Finish when done."
                     : repState == .scoring
                     ? "Scoring your rep…"
                     : "When you're ready, tap Start. We'll record your movement.")
                    .foregroundStyle(.secondary)
                if repState == .scoring {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Scoring…")
                    }
                    .font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.gray.opacity(0.12), in: .rect(cornerRadius: 14))

            liveScoreRing
        }
    }

    private var resultSlide: some View {
        VStack(spacing: 20) {
            let score = lastScore ?? 0
            Text("\(score)")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundStyle(score.scoreColor)
                .contentTransition(.numericText())
            Text(lastFeedback)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var compositeScore: Int {
        let all = attemptResults.flatMap { $0 }
        guard !all.isEmpty else { return 0 }
        return all.reduce(0, +) / all.count
    }

    private var summarySlide: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                let scores = index < attemptResults.count ? attemptResults[index] : []
                let avg = scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: exercise.systemImage)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading) {
                        Text(exercise.name)
                            .font(.headline)
                        Text(scores.isEmpty
                             ? "No reps recorded"
                             : "\(scores.count) rep\(scores.count == 1 ? "" : "s") · avg \(avg)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !scores.isEmpty {
                        Text("\(avg)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(avg.scoreColor)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.12), in: .rect(cornerRadius: 12))
            }

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: CGFloat(compositeScore) / 100)
                        .stroke(compositeScore.scoreColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.8), value: compositeScore)
                    Text("\(compositeScore)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                }
                .frame(width: 130, height: 130)
                Text("Session Score")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

        }
    }

    private var navigationTitle: String {
        switch slide {
        case .intro: return "Instructions"
        case .perform: return "Perform"
        case .result: return "Result"
        case .summary: return "Summary"
        }
    }

    // MARK: - Haptics
    private func hapticImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func hapticNotify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    // MARK: - Actions
    private func startAttempt() {
        guard repState == .idle else { return }
        hapticImpact(.medium)
        repStartTime = ble.payloadHistory.last?.time ?? 0
        repStartDate = Date()
        liveScore = nil
        repState = .recording
    }

    private func finishAttempt() {
        guard repState == .recording else { return }
        repState = .scoring
        let cutoff = repStartTime
        let repPayloads = ble.payloadHistory.filter { $0.time > cutoff }.map(\.payload)
        let payloads = repPayloads.count >= 2 ? repPayloads : ble.payloadHistory.map(\.payload)
        Task { @MainActor in
            let score = await scorer.scoreRep(payloads: payloads)
            lastScore = score
            lastFeedback = repFeedback(score)
            switch score {
            case 80...: hapticNotify(.success)
            case 60..<80: hapticNotify(.warning)
            default: hapticNotify(.error)
            }
            if attemptResults.indices.contains(currentExerciseIndex) {
                attemptResults[currentExerciseIndex].append(score)
            }
            repState = .idle
            slide = .result
        }
    }

    private func saveSession() {
        let results = exercises.enumerated().map { index, exercise in
            let scores = index < attemptResults.count ? attemptResults[index] : []
            return ExerciseResult(
                exerciseId: exercise.id,
                exerciseName: exercise.name,
                systemImage: exercise.systemImage,
                repScores: scores
            )
        }
        let session = SessionRecord(
            date: Date(),
            compositeScore: compositeScore,
            exerciseResults: results
        )
        modelContext.insert(session)
    }

    private func advanceToNextExercise() {
        if currentExerciseIndex < totalExercises - 1 {
            currentExerciseIndex += 1
            slide = .intro
        } else {
            slide = .summary
        }
    }
}

#Preview {
    NavigationStack {
        ExerciseFlowView(exercises: Array(Exercise.catalog.prefix(3)))
            .environmentObject(BLEManager())
            .environmentObject(RepScorer())
    }
}
