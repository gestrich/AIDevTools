import Foundation

public struct LogReaderService: Sendable {
    private let fileURL: URL

    public init(fileURL: URL = AIDevToolsLogging.defaultLogFileURL) {
        self.fileURL = fileURL
    }

    public func readAll() throws -> [LogEntry] {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let decoder = JSONDecoder()
        return content
            .split(separator: "\n")
            .compactMap { line in
                try? decoder.decode(LogEntry.self, from: Data(line.utf8))
            }
    }

    public func readByDateRange(from start: Date, to end: Date) throws -> [LogEntry] {
        try readAll().filter { entry in
            guard let date = entry.date else { return false }
            return date >= start && date <= end
        }
    }

    public func readLastRun(marker: String) throws -> [LogEntry] {
        let all = try readAll()
        guard let lastStartIndex = all.lastIndex(where: { $0.message == marker }) else {
            return []
        }
        return Array(all[lastStartIndex...])
    }

    public func clearLogs() throws {
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.truncate(atOffset: 0)
        try handle.close()
    }

    public func readRuns(marker: String) throws -> [[LogEntry]] {
        let all = try readAll()
        var runs: [[LogEntry]] = []
        var currentRun: [LogEntry] = []

        for entry in all {
            if entry.message == marker {
                if !currentRun.isEmpty {
                    runs.append(currentRun)
                }
                currentRun = [entry]
            } else {
                currentRun.append(entry)
            }
        }

        if !currentRun.isEmpty {
            runs.append(currentRun)
        }

        return runs
    }
}
