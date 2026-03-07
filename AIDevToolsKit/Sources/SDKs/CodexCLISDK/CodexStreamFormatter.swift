import Foundation

public final class CodexStreamFormatter: Sendable {
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
        guard let event = try? decoder.decode(CodexFormatterEvent.self, from: data) else { return nil }

        switch event.type {
        case "item.completed":
            return formatItem(event.item)
        case "turn.completed":
            return formatTurnCompleted(event.usage)
        default:
            return nil
        }
    }

    private func formatItem(_ item: CodexFormatterItem?) -> String? {
        guard let item else { return nil }
        switch item.type {
        case "agent_message":
            if let text = item.text, !text.isEmpty {
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let reasoning = json["result"] as? String, !reasoning.isEmpty {
                        let preview = String(reasoning.prefix(200))
                        let suffix = reasoning.count > 200 ? "..." : ""
                        return "[Thinking] \(preview)\(suffix)\n"
                    }
                    return nil
                }
                return text + "\n"
            }
        case "command_execution":
            var parts: [String] = []
            if let cmd = item.command {
                parts.append("[Command] \(cmd)")
            }
            if let output = item.aggregatedOutput, !output.isEmpty {
                parts.append(output)
            }
            if let exit = item.exitCode, exit != 0 {
                parts.append("Exit code: \(exit)")
            }
            if !parts.isEmpty {
                return parts.joined(separator: "\n") + "\n"
            }
        default:
            break
        }
        return nil
    }

    private func formatTurnCompleted(_ usage: CodexFormatterUsage?) -> String? {
        guard let usage else { return nil }
        var parts: [String] = ["--- Turn Complete ---"]
        if let input = usage.inputTokens {
            parts.append("Input: \(input) tokens")
        }
        if let output = usage.outputTokens {
            parts.append("Output: \(output) tokens")
        }
        return parts.joined(separator: " | ") + "\n"
    }
}

private struct CodexFormatterEvent: Codable {
    let type: String
    let item: CodexFormatterItem?
    let usage: CodexFormatterUsage?
}

private struct CodexFormatterItem: Codable {
    let type: String
    let text: String?
    let command: String?
    let aggregatedOutput: String?
    let exitCode: Int?

    enum CodingKeys: String, CodingKey {
        case type, text, command
        case aggregatedOutput = "aggregated_output"
        case exitCode = "exit_code"
    }
}

private struct CodexFormatterUsage: Codable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}
