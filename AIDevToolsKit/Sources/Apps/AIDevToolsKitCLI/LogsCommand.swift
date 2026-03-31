import ArgumentParser
import Foundation
import LoggingSDK

struct LogsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "View AIDevTools log entries"
    )

    @Option(name: .long, help: "Start date (YYYY-MM-DD)")
    var from: String?

    @Option(name: .long, help: "End date (YYYY-MM-DD)")
    var to: String?

    @Option(name: .long, help: "Filter by log level (trace, debug, info, notice, warning, error, critical)")
    var level: String?

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func validate() throws {
        if (from != nil) != (to != nil) {
            throw ValidationError("Both --from and --to must be specified together")
        }
    }

    func run() throws {
        let reader = LogReaderService()

        var entries: [LogEntry]
        if let fromStr = from, let toStr = to {
            guard let fromDate = parseDate(fromStr) else {
                throw ValidationError("Invalid --from date '\(fromStr)'. Use YYYY-MM-DD format.")
            }
            guard let toDate = parseDate(toStr) else {
                throw ValidationError("Invalid --to date '\(toStr)'. Use YYYY-MM-DD format.")
            }
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: toDate)!
            entries = try reader.readByDateRange(from: fromDate, to: endOfDay)
        } else {
            entries = try reader.readAll()
        }

        if let level {
            entries = entries.filter { $0.level == level }
        }

        if entries.isEmpty {
            print("No log entries found.")
            return
        }

        if json {
            let data = try JSONEncoder().encode(entries)
            print(String(data: data, encoding: .utf8)!)
        } else {
            for entry in entries {
                let metaStr: String
                if let metadata = entry.metadata, !metadata.isEmpty {
                    metaStr = " " + metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
                } else {
                    metaStr = ""
                }
                let color = levelColor(entry.level)
                print("\(entry.timestamp) \(color)[\(entry.level.uppercased())]\(ANSIColor.reset.rawValue) \(entry.label): \(entry.message)\(metaStr)")
            }
        }
    }

    private func levelColor(_ level: String) -> String {
        switch level {
        case "critical", "error": return ANSIColor.red.rawValue
        case "warning": return ANSIColor.yellow.rawValue
        case "info", "notice": return ANSIColor.green.rawValue
        case "debug", "trace": return "\u{001B}[90m"
        default: return ""
        }
    }

    private func parseDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value + "T00:00:00Z")
    }
}
