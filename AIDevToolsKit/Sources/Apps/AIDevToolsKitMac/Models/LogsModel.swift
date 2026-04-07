import Foundation
import LoggingSDK
import LogsFeature
import Observation

@MainActor
@Observable
final class LogsModel {
    private(set) var state: ModelState = .loading
    var searchText: String = ""
    private var hasLoaded = false
    private var nextID = 0

    var items: [LogItem] {
        if case .streaming(let items) = state { return items }
        return []
    }

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
        state = .loading
        do {
            for try await entries in StreamLogsUseCase().stream() {
                append(entries)
            }
        } catch {
            state = .error(error)
        }
    }

    func deleteLogs() {
        // Truncate rather than delete so the DispatchSource in LogFileWatcher
        // keeps its file descriptor and streaming resumes for new entries.
        do {
            try LogReaderService().clearLogs()
        } catch {
            state = .error(error)
            return
        }
        state = .streaming([])
        nextID = 0
    }

    private func append(_ entries: [LogEntry]) {
        let newItems = entries.enumerated().map { offset, entry in
            LogItem(id: nextID + offset, entry: entry)
        }
        nextID += entries.count
        state = .streaming(items + newItems)
    }

    enum ModelState {
        case error(Error)
        case loading
        case streaming([LogItem])
    }
}
