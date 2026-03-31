import Foundation
import LoggingSDK
import Observation

struct LogItem: Identifiable {
    let id: Int
    let entry: LogEntry
}

@Observable
@MainActor
final class LogsModel {
    private(set) var items: [LogItem] = []
    var searchText: String = ""
    private(set) var isLoading = false
    private var hasLoaded = false
    private var nextID = 0

    var filteredItems: [LogItem] {
        guard !searchText.isEmpty else { return items }
        let query = searchText.lowercased()
        return items.filter { item in
            item.entry.message.lowercased().contains(query) ||
            item.entry.label.lowercased().contains(query) ||
            item.entry.level.lowercased().contains(query) ||
            (item.entry.source?.lowercased().contains(query) ?? false)
        }
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        isLoading = true
        let reader = LogReaderService()
        let existing = (try? reader.readAll()) ?? []
        append(existing)
        isLoading = false

        for await newEntries in LogFileWatcher().stream() {
            append(newEntries)
        }
    }

    func deleteLogs() {
        // Truncate rather than delete so the DispatchSource in LogFileWatcher
        // keeps its file descriptor and streaming resumes for new entries.
        if let handle = try? FileHandle(forWritingTo: AIDevToolsLogging.defaultLogFileURL) {
            try? handle.truncate(atOffset: 0)
            try? handle.close()
        }
        items = []
        nextID = 0
    }

    private func append(_ entries: [LogEntry]) {
        let newItems = entries.enumerated().map { offset, entry in
            LogItem(id: nextID + offset, entry: entry)
        }
        nextID += entries.count
        items.append(contentsOf: newItems)
    }
}
