import AVFoundation
import Foundation

@MainActor
final class SpeechManager: ObservableObject {

    private enum Config {
        // development only — move to a backend token before shipping
        static let apiKey = "REPLACE WITH API KEY"
        static let voiceId = "21m00Tcm4TlvDq8ikWAM" // Rachel — calm, clear
    }

    private var player: AVAudioPlayer?

    func speak(_ text: String) async {
        stop()

        var request = URLRequest(
            url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(Config.voiceId)")!
        )
        request.httpMethod = "POST"
        request.setValue(Config.apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": "eleven_turbo_v2_5",
            "output_format": "mp3_22050_32"
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(data: data)
            player?.play()
        } catch {
            // speech is non-critical — the exercise flow continues regardless
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }
}
