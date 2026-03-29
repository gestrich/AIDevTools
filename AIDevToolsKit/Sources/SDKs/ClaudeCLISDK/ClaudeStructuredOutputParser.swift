import CLISDK
import Foundation
import Logging

public struct ClaudeStructuredOutput<T: Sendable>: Sendable {
    public let rawOutput: String
    public let resultEvent: ClaudeResultEvent
    public let stderr: String
    public let value: T
}

public struct ProcessDiagnostics: Sendable {
    public let exitCode: Int32
    public let stderrSnippet: String
    public let stdoutLineCount: Int
    public let stdoutByteCount: Int

    /// Counts of each event type seen in the JSONL stream (e.g. ["system": 1, "assistant": 5])
    public var eventTypeCounts: [String: Int] = [:]
    /// Number of stdout lines that failed JSON decoding as a ClaudeEventEnvelope
    public var jsonDecodeFailures: Int = 0
    /// Number of lines whose envelope decoded as type "result" but failed to decode as ClaudeResultEvent
    public var resultEventDecodeFailures: Int = 0
    /// Session ID from the system init event, if found
    public var sessionId: String?
    /// Last 1000 characters of stdout for context (trailing whitespace stripped)
    public var stdoutTail: String = ""

    public init(exitCode: Int32, stderr: String, stdout: String) {
        self.exitCode = exitCode
        let lines = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .suffix(5)
        self.stderrSnippet = lines.joined(separator: "\n")
        self.stdoutLineCount = stdout.components(separatedBy: "\n").count
        self.stdoutByteCount = stdout.utf8.count
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        self.stdoutTail = String(trimmed.suffix(1000))
    }

    public var summary: String {
        var parts = ["exit=\(exitCode)", "stdout=\(stdoutLineCount) lines/\(stdoutByteCount) bytes"]
        if !eventTypeCounts.isEmpty {
            let sorted = eventTypeCounts.sorted { $0.key < $1.key }
            let counts = sorted.map { "\($0.key):\($0.value)" }.joined(separator: " ")
            parts.append("events=[\(counts)]")
        }
        if jsonDecodeFailures > 0 {
            parts.append("json_failures=\(jsonDecodeFailures)")
        }
        if resultEventDecodeFailures > 0 {
            parts.append("result_decode_failures=\(resultEventDecodeFailures)")
        }
        if let sessionId {
            parts.append("session=\(sessionId)")
        }
        if !stderrSnippet.isEmpty {
            parts.append("stderr: \(stderrSnippet.prefix(300))")
        }
        if !stdoutTail.isEmpty {
            parts.append("stdout_tail: \(stdoutTail)")
        }
        return parts.joined(separator: ", ")
    }
}

public enum ClaudeStructuredOutputError: Error, LocalizedError {
    case noResultEvent(ProcessDiagnostics?)
    case resultError(resultEvent: ClaudeResultEvent)
    case missingStructuredOutput(resultEvent: ClaudeResultEvent)
    case decodingFailed(Error, resultEvent: ClaudeResultEvent)

    public var errorDescription: String? {
        switch self {
        case .noResultEvent(let diagnostics):
            var message = "Claude CLI returned no result event."
            if let diagnostics {
                message += " Process diagnostics: \(diagnostics.summary)"
            } else {
                message += " The process may have exited early or produced no output."
            }
            return message
        case .resultError(let resultEvent):
            var parts = ["Claude CLI returned an error"]
            if let subtype = resultEvent.subtype { parts.append("(\(subtype))") }
            if let errors = resultEvent.errors { parts.append(": \(errors)") }
            parts.append(resultEvent.diagnosticSummary)
            return parts.joined(separator: " ")
        case .missingStructuredOutput(let resultEvent):
            return "Claude CLI result contained no structured output. \(resultEvent.diagnosticSummary)"
        case .decodingFailed(let error, let resultEvent):
            return "Failed to decode Claude CLI response: \(error.localizedDescription). \(resultEvent.diagnosticSummary)"
        }
    }
}

public struct ClaudeStructuredOutputParser: Sendable {

    private let logger = Logger(label: "ClaudeStructuredOutputParser")

    public init() {}

    public func parse<T: Decodable & Sendable>(_ type: T.Type, from result: ExecutionResult) throws -> ClaudeStructuredOutput<T> {
        let diagnostics = ProcessDiagnostics(exitCode: result.exitCode, stderr: result.stderr, stdout: result.stdout)
        let resultEvent = try findResultEvent(in: result.stdout, diagnostics: diagnostics)

        // Use subtype as the authoritative success signal, matching claude-code-action behavior.
        // The is_error field should align with subtype but is not the primary indicator.
        if resultEvent.subtype != "success" {
            throw ClaudeStructuredOutputError.resultError(resultEvent: resultEvent)
        }

        guard let structuredJSON = resultEvent.structuredOutput else {
            throw ClaudeStructuredOutputError.missingStructuredOutput(resultEvent: resultEvent)
        }

        let encoded = try JSONEncoder().encode(structuredJSON)
        do {
            let decoded = try JSONDecoder().decode(T.self, from: encoded)
            return ClaudeStructuredOutput(rawOutput: result.stdout, resultEvent: resultEvent, stderr: result.stderr, value: decoded)
        } catch {
            throw ClaudeStructuredOutputError.decodingFailed(error, resultEvent: resultEvent)
        }
    }

    public func findResultEvent(in stdout: String, diagnostics: ProcessDiagnostics? = nil) throws -> ClaudeResultEvent {
        let decoder = JSONDecoder()
        var lastResult: ClaudeResultEvent?
        var enrichedDiagnostics = diagnostics
        var eventTypeCounts: [String: Int] = [:]
        var jsonDecodeFailures = 0
        var resultEventDecodeFailures = 0
        var sessionId: String?

        for line in stdout.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }

            let envelope: ClaudeEventEnvelope
            do {
                envelope = try decoder.decode(ClaudeEventEnvelope.self, from: data)
            } catch {
                jsonDecodeFailures += 1
                logger.error("Failed to decode event envelope: \(error.localizedDescription)", metadata: [
                    "line_preview": "\(trimmed.prefix(500))",
                    "line_length": "\(trimmed.count)"
                ])
                continue
            }

            eventTypeCounts[envelope.type, default: 0] += 1

            if envelope.type == ClaudeEventType.system, sessionId == nil {
                sessionId = (try? decoder.decode(ClaudeSystemEvent.self, from: data))?.sessionId
            }

            guard envelope.type == ClaudeEventType.result else { continue }

            do {
                let event = try decoder.decode(ClaudeResultEvent.self, from: data)
                lastResult = event
            } catch {
                // A line with type="result" was present but couldn't be decoded into ClaudeResultEvent.
                // This is distinct from a missing result event — the envelope was valid but the shape
                // of the result payload was unexpected. Track separately so diagnostics show both cases.
                resultEventDecodeFailures += 1
                logger.error("Found result envelope but failed to decode as ClaudeResultEvent: \(error.localizedDescription)", metadata: [
                    "line_preview": "\(trimmed.prefix(500))",
                    "line_length": "\(trimmed.count)"
                ])
            }
        }

        guard let result = lastResult else {
            enrichedDiagnostics?.eventTypeCounts = eventTypeCounts
            enrichedDiagnostics?.jsonDecodeFailures = jsonDecodeFailures
            enrichedDiagnostics?.resultEventDecodeFailures = resultEventDecodeFailures
            enrichedDiagnostics?.sessionId = sessionId
            throw ClaudeStructuredOutputError.noResultEvent(enrichedDiagnostics)
        }
        return result
    }
}
