import Foundation

// Call only from the main thread (BLEManager already does this via queue: .main)
final class AppLogger: ObservableObject {
    static let shared = AppLogger()
    private init() {}

    enum Level: String, CaseIterable {
        case debug   = "DEBUG"
        case info    = "INFO"
        case warning = "WARN"
        case error   = "ERROR"
        case data    = "DATA"
    }

    struct Entry: Identifiable {
        let id   = UUID()
        let date = Date()
        let level: Level
        let message: String
    }

    @Published private(set) var entries: [Entry] = []
    private static let maxEntries = 1000

    func log(_ message: String, level: Level = .info) {
        entries.append(Entry(level: level, message: message))
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    func clear() { entries.removeAll() }

    var plainText: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        return entries
            .map { "[\(fmt.string(from: $0.date))][\($0.level.rawValue)] \($0.message)" }
            .joined(separator: "\n")
    }
}

// Shorthand so call sites stay concise
func appLog(_ message: String, level: AppLogger.Level = .info) {
    AppLogger.shared.log(message, level: level)
}
