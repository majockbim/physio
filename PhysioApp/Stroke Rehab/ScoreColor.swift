import SwiftUI
import Foundation

extension Int {
    var scoreColor: Color {
        switch self {
        case 80...: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }
}

extension Date {
    var sessionLabel: String {
        if Calendar.current.isDateInToday(self) { return "Today" }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.month(.abbreviated).day())
    }
}
