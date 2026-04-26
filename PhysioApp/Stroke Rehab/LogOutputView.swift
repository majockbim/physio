import SwiftUI

struct LogOutputView: View {
    @ObservedObject private var logger = AppLogger.shared
    @State private var selectedLevel: AppLogger.Level? = nil
    @State private var autoScroll = true

    private var displayed: [AppLogger.Entry] {
        guard let level = selectedLevel else { return logger.entries }
        return logger.entries.filter { $0.level == level }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            logList
        }
        .navigationTitle("Log Output")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Clear", role: .destructive) { logger.clear() }
                    .foregroundStyle(.red)
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Toggle(isOn: $autoScroll) {
                    Image(systemName: "arrow.down.to.line")
                }
                .toggleStyle(.button)
                .tint(.accentColor)

                ShareLink(item: logger.plainText) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                levelChip(nil, label: "All")
                ForEach(AppLogger.Level.allCases, id: \.self) { level in
                    levelChip(level, label: level.rawValue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func levelChip(_ level: AppLogger.Level?, label: String) -> some View {
        let active = selectedLevel == level
        return Button {
            selectedLevel = level
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(active ? chipColor(level) : Color.gray.opacity(0.15), in: .capsule)
                .foregroundStyle(active ? .white : .primary)
        }
    }

    private func chipColor(_ level: AppLogger.Level?) -> Color {
        guard let level else { return .accentColor }
        return entryColor(level)
    }

    // MARK: - Log list

    private var logList: some View {
        ScrollViewReader { proxy in
            List(displayed) { entry in
                EntryRow(entry: entry)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                    .id(entry.id)
            }
            .listStyle(.plain)
            .font(.system(.caption, design: .monospaced))
            .onChange(of: logger.entries.count) { _, _ in
                guard autoScroll, let last = displayed.last else { return }
                withAnimation(.none) { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .overlay {
                if displayed.isEmpty {
                    ContentUnavailableView("No Logs", systemImage: "doc.text",
                                          description: Text("Events will appear here as they occur."))
                }
            }
        }
    }
}

// MARK: - Entry row

private struct EntryRow: View {
    let entry: AppLogger.Entry
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(Self.timeFmt.string(from: entry.date))
                .foregroundStyle(.secondary)
                .fixedSize()

            Text(entry.level.rawValue)
                .foregroundStyle(entryColor(entry.level))
                .frame(width: 42, alignment: .leading)

            Text(entry.message)
                .foregroundStyle(entry.level == .debug ? .secondary : .primary)
                .textSelection(.enabled)
        }
        .font(.system(size: 11, design: .monospaced))
    }
}

private func entryColor(_ level: AppLogger.Level) -> Color {
    switch level {
    case .debug:   return .secondary
    case .info:    return .primary
    case .warning: return .orange
    case .error:   return .red
    case .data:    return .blue
    }
}

#Preview {
    NavigationStack { LogOutputView() }
}
