import AIOutputSDK
import Foundation
import Logging

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

public final class ClaudeStreamFormatter: StreamFormatter, Sendable {
    private let decoder = JSONDecoder()
    private let logger = Logger(label: "ClaudeStreamFormatter")

    public init() {}

    public func format(_ rawChunk: String) -> String {
        var output = ""
        for line in rawChunk.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            if let formatted = formatLine(data, rawLine: trimmed) {
                output += formatted
            }
        }
        return output
    }

    private func formatLine(_ data: Data, rawLine: String) -> String? {
        let envelope: ClaudeEventEnvelope
        do {
            envelope = try decoder.decode(ClaudeEventEnvelope.self, from: data)
        } catch {
            return rawLine + "\n"
        }

        let lineMetadata: Logger.Metadata = ["type": "\(envelope.type)", "line": "\(rawLine.prefix(200))"]

        switch envelope.type {
        case ClaudeEventType.assistant:
            do {
                let event = try decoder.decode(ClaudeAssistantEvent.self, from: data)
                return formatAssistantEvent(event)
            } catch {
                logger.error("Failed to decode assistant event: \(error.localizedDescription)", metadata: lineMetadata)
            }
        case ClaudeEventType.user:
            do {
                let event = try decoder.decode(ClaudeUserEvent.self, from: data)
                return formatUserEvent(event)
            } catch {
                logger.error("Failed to decode user event: \(error.localizedDescription)", metadata: lineMetadata)
            }
        case ClaudeEventType.result:
            do {
                let event = try decoder.decode(ClaudeResultSummary.self, from: data)
                return formatResultEvent(event)
            } catch {
                logger.error("Failed to decode result event: \(error.localizedDescription)", metadata: lineMetadata)
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

    private func toolUseDetail(name: String, input: [String: JSONValue]?) -> String {
        switch name {
        case ClaudeToolName.bash:
            return input?[ClaudeToolInputKey.command]?.stringValue ?? ""
        case "Read":
            return input?["file_path"]?.stringValue ?? ""
        case "Edit":
            return input?["file_path"]?.stringValue ?? ""
        case "Write":
            return input?["file_path"]?.stringValue ?? ""
        case "Grep":
            let pattern = input?["pattern"]?.stringValue ?? ""
            let path = input?["path"]?.stringValue ?? ""
            return "\(pattern) in \(path)"
        case "Glob":
            return input?["pattern"]?.stringValue ?? ""
        default:
            return input.map { Array($0.keys).sorted().joined(separator: ", ") } ?? ""
        }
    }

    private func formatToolUse(name: String, input: [String: JSONValue]?) -> String {
        "[\(name)] \(toolUseDetail(name: name, input: input))"
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

    // MARK: - Structured Parsing

    public func formatStructured(_ rawChunk: String) -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []
        for line in rawChunk.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            events.append(contentsOf: parseStreamEvents(data, rawLine: trimmed))
        }
        return events
    }

    private func parseStreamEvents(_ data: Data, rawLine: String) -> [AIStreamEvent] {
        let envelope: ClaudeEventEnvelope
        do {
            envelope = try decoder.decode(ClaudeEventEnvelope.self, from: data)
        } catch {
            return [.textDelta(rawLine + "\n")]
        }

        switch envelope.type {
        case ClaudeEventType.assistant:
            do {
                let event = try decoder.decode(ClaudeAssistantEvent.self, from: data)
                return parseAssistantStreamEvents(event)
            } catch {
                logger.error("Failed to decode assistant event for structured parse: \(error.localizedDescription)")
                return []
            }
        case ClaudeEventType.user:
            do {
                let event = try decoder.decode(ClaudeUserEvent.self, from: data)
                return parseUserStreamEvents(event)
            } catch {
                logger.error("Failed to decode user event for structured parse: \(error.localizedDescription)")
                return []
            }
        case ClaudeEventType.result:
            do {
                let event = try decoder.decode(ClaudeResultSummary.self, from: data)
                return parseResultStreamEvents(event)
            } catch {
                logger.error("Failed to decode result event for structured parse: \(error.localizedDescription)")
                return []
            }
        default:
            return []
        }
    }

    private func parseAssistantStreamEvents(_ event: ClaudeAssistantEvent) -> [AIStreamEvent] {
        guard let content = event.message?.content, !content.isEmpty else { return [] }
        var events: [AIStreamEvent] = []

        for block in content {
            switch block.type {
            case "thinking":
                if let thinking = block.thinking, !thinking.isEmpty {
                    events.append(.thinking(thinking))
                }
            case "text":
                if let text = block.text, !text.isEmpty {
                    events.append(.textDelta(text))
                }
            case ClaudeContentBlockType.toolUse:
                if let name = block.name, name != ClaudeToolName.structuredOutput {
                    let detail = toolUseDetail(name: name, input: block.input)
                    events.append(.toolUse(name: name, detail: detail))
                }
            default:
                break
            }
        }

        return events
    }

    private func parseUserStreamEvents(_ event: ClaudeUserEvent) -> [AIStreamEvent] {
        guard let content = event.message?.content, !content.isEmpty else { return [] }
        var events: [AIStreamEvent] = []

        for block in content {
            if block.type == ClaudeContentBlockType2.toolResult {
                let isError = block.isError ?? false
                if let summary = block.content?.summary, !summary.isEmpty {
                    events.append(.toolResult(name: "", summary: summary, isError: isError))
                }
            }
        }

        return events
    }

    private func parseResultStreamEvents(_ event: ClaudeResultSummary) -> [AIStreamEvent] {
        let duration: TimeInterval? = event.durationMs.map { Double($0) / 1000.0 }
        return [.metrics(duration: duration, cost: event.totalCostUsd, turns: event.numTurns)]
    }
}
