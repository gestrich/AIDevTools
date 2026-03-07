import Foundation

public struct ClaudeResultSummary: Codable, Sendable {
    public let type: String
    public let isError: Bool?
    public let subtype: String?
    public let durationMs: Int?
    public let totalCostUsd: Double?
    public let numTurns: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case isError = "is_error"
        case subtype
        case durationMs = "duration_ms"
        case totalCostUsd = "total_cost_usd"
        case numTurns = "num_turns"
    }
}

public final class ClaudeStreamFormatter: Sendable {
    private let decoder = JSONDecoder()

    public init() {}

    public func format(_ rawChunk: String) -> String {
        var output = ""
        for line in rawChunk.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            if let formatted = formatLine(data) {
                output += formatted
            }
        }
        return output
    }

    private func formatLine(_ data: Data) -> String? {
        guard let raw = try? decoder.decode([String: JSONValue].self, from: data),
              let typeValue = raw["type"]?.stringValue else { return nil }

        switch typeValue {
        case ClaudeEventType.assistant:
            if let event = try? decoder.decode(ClaudeAssistantEvent.self, from: data) {
                return formatAssistantEvent(event)
            }
        case ClaudeEventType.user:
            if let event = try? decoder.decode(ClaudeUserEvent.self, from: data) {
                return formatUserEvent(event)
            }
        case ClaudeEventType.result:
            if let event = try? decoder.decode(ClaudeResultSummary.self, from: data) {
                return formatResultEvent(event)
            }
        default:
            break
        }

        return nil
    }

    private func formatAssistantEvent(_ event: ClaudeAssistantEvent) -> String? {
        guard let content = event.message?.content, !content.isEmpty else { return nil }
        var parts: [String] = []

        for block in content {
            switch block.type {
            case "thinking":
                if let thinking = block.thinking, !thinking.isEmpty {
                    parts.append("[Thinking] \(thinking)")
                }
            case "text":
                if let text = block.text, !text.isEmpty {
                    parts.append(text)
                }
            case ClaudeContentBlockType.toolUse:
                if let name = block.name, name != ClaudeToolName.structuredOutput {
                    parts.append(formatToolUse(name: name, input: block.input))
                }
            default:
                break
            }
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n") + "\n"
    }

    private func formatToolUse(name: String, input: [String: JSONValue]?) -> String {
        switch name {
        case ClaudeToolName.bash:
            let cmd = input?[ClaudeToolInputKey.command]?.stringValue ?? ""
            return "[Bash] \(cmd)"
        case "Read":
            let path = input?["file_path"]?.stringValue ?? ""
            return "[Read] \(path)"
        case "Edit":
            let path = input?["file_path"]?.stringValue ?? ""
            return "[Edit] \(path)"
        case "Write":
            let path = input?["file_path"]?.stringValue ?? ""
            return "[Write] \(path)"
        case "Grep":
            let pattern = input?["pattern"]?.stringValue ?? ""
            let path = input?["path"]?.stringValue ?? ""
            return "[Grep] \(pattern) in \(path)"
        case "Glob":
            let pattern = input?["pattern"]?.stringValue ?? ""
            return "[Glob] \(pattern)"
        default:
            let keys = input.map { Array($0.keys).sorted().joined(separator: ", ") } ?? ""
            return "[\(name)] \(keys)"
        }
    }

    private func formatUserEvent(_ event: ClaudeUserEvent) -> String? {
        guard let content = event.message?.content, !content.isEmpty else { return nil }
        var parts: [String] = []

        for block in content {
            if block.type == ClaudeContentBlockType2.toolResult {
                if let summary = block.content?.summary, !summary.isEmpty {
                    parts.append("  → \(summary)")
                }
            }
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n") + "\n"
    }

    private func formatResultEvent(_ event: ClaudeResultSummary) -> String {
        var parts: [String] = ["--- Result ---"]
        if event.isError == true {
            parts.append("Error: \(event.subtype ?? "unknown")")
        }
        if let ms = event.durationMs {
            let seconds = Double(ms) / 1000.0
            parts.append(String(format: "Duration: %.1fs", seconds))
        }
        if let cost = event.totalCostUsd {
            parts.append(String(format: "Cost: $%.4f", cost))
        }
        if let turns = event.numTurns {
            parts.append("Turns: \(turns)")
        }
        return parts.joined(separator: " | ") + "\n"
    }
}
