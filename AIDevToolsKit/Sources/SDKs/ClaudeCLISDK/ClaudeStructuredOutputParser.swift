import Foundation

public struct ClaudeStructuredOutput<T: Sendable>: Sendable {
    public let value: T
    public let resultEvent: ClaudeResultEvent
}

public enum ClaudeStructuredOutputError: Error, LocalizedError {
    case noResultEvent
    case resultError(subtype: String?, errors: JSONValue?)
    case missingStructuredOutput
    case decodingFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .noResultEvent:
            return "Claude CLI returned no result event. The process may have exited early or produced no output."
        case .resultError(let subtype, let errors):
            var parts = ["Claude CLI returned an error"]
            if let subtype { parts.append("(\(subtype))") }
            if let errors { parts.append(": \(errors)") }
            return parts.joined(separator: " ")
        case .missingStructuredOutput:
            return "Claude CLI result contained no structured output. The response may have been empty."
        case .decodingFailed(let error):
            return "Failed to decode Claude CLI response: \(error.localizedDescription)"
        }
    }
}

public struct ClaudeStructuredOutputParser: Sendable {

    public init() {}

    public func parse<T: Decodable & Sendable>(_ type: T.Type, from stdout: String) throws -> ClaudeStructuredOutput<T> {
        let resultEvent = try findResultEvent(in: stdout)

        if resultEvent.isError == true {
            throw ClaudeStructuredOutputError.resultError(
                subtype: resultEvent.subtype,
                errors: resultEvent.errors
            )
        }

        guard let structuredJSON = resultEvent.structuredOutput else {
            throw ClaudeStructuredOutputError.missingStructuredOutput
        }

        let encoded = try JSONEncoder().encode(structuredJSON)
        do {
            let decoded = try JSONDecoder().decode(T.self, from: encoded)
            return ClaudeStructuredOutput(value: decoded, resultEvent: resultEvent)
        } catch {
            throw ClaudeStructuredOutputError.decodingFailed(error)
        }
    }

    public func findResultEvent(in stdout: String) throws -> ClaudeResultEvent {
        let decoder = JSONDecoder()
        var lastResult: ClaudeResultEvent?

        for line in stdout.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }

            guard let raw = try? decoder.decode([String: JSONValue].self, from: data),
                  raw["type"]?.stringValue == ClaudeEventType.result else { continue }

            if let event = try? decoder.decode(ClaudeResultEvent.self, from: data) {
                lastResult = event
            }
        }

        guard let result = lastResult else {
            throw ClaudeStructuredOutputError.noResultEvent
        }
        return result
    }
}
