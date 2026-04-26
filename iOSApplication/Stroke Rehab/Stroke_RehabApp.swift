import SwiftUI
import SwiftData

@main
struct Stroke_RehabApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SessionRecord.self)
    }
}
