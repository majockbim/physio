import Foundation
@preconcurrency import ZeticMLange

@MainActor
final class RepScorer: ObservableObject {
    @Published var latestScore: Int? = nil
    @Published var downloadProgress: Double? = nil
    @Published var isRunning = false
    @Published var errorMessage: String? = nil

    var isModelLoaded: Bool { model != nil }

    private var model: ZeticMLangeModel? = nil

    // MARK: - Developer screen: fire-and-forget, updates published state

    func run(payloads: [SensorPayload]) {
        guard !isRunning else { return }
        guard payloads.count >= 2 else {
            errorMessage = "Not enough sensor data (\(payloads.count) samples)"
            return
        }
        isRunning = true
        errorMessage = nil
        Task {
            do {
                latestScore = try await score(payloads: payloads)
            } catch {
                errorMessage = error.localizedDescription
            }
            isRunning = false
        }
    }

    // MARK: - Session use: returns score directly, no isRunning gating

    func scoreRep(payloads: [SensorPayload]) async -> Int {
        guard payloads.count >= 2 else { return 0 }
        do {
            return try await score(payloads: payloads)
        } catch {
            errorMessage = error.localizedDescription
            return 0
        }
    }

    // MARK: - Core pipeline

    private func score(payloads: [SensorPayload]) async throws -> Int {
        if model == nil {
            downloadProgress = 0.0
            model = try await loadModel()
            downloadProgress = nil
        }
        return try await infer(payloads: payloads)
    }

    private func loadModel() async throws -> ZeticMLangeModel {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let mdl = try ZeticMLangeModel(
                        personalKey: "dev_98e6fcc313ed4ffea8198bc9982f4779",
                        name: "Popcorn101/Strokr",
                        version: 3,
                        modelMode: .RUN_AUTO
                    ) { [weak self] progress in
                        Task { @MainActor [weak self] in self?.downloadProgress = Double(progress) }
                    }
                    cont.resume(returning: mdl)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func infer(payloads: [SensorPayload]) async throws -> Int {
        let mdl = model!
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    cont.resume(returning: try MovementQualityInference.getLiveScore(from: payloads, using: mdl))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}
