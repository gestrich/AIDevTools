import CLISDK
import Foundation
import Logging

public struct ClaudeStructuredOutput<T: Sendable>: Sendable {
    public let value: T
    public let resultEvent: ClaudeResultEvent
}

public struct ProcessDiagnostics: Sendable {
    public let exitCode: Int32
    public let stderrSnippet: String
    public let stdoutLineCount: Int
    public let stdoutByteCount: Int

    public init(exitCode: Int32, stderr: String, stdout: String) {
        self.exitCode = exitCode
        let lines = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .suffix(5)
        self.stderrSnippet = lines.joined(separator: "\n")
        self.stdoutLineCount = stdout.components(separatedBy: "\n").count
        self.stdoutByteCount = stdout.utf8.count
    }

    public var summary: String {
        var parts = ["exit=\(exitCode)", "stdout=\(stdoutLineCount) lines/\(stdoutByteCount) bytes"]
        if !stderrSnippet.isEmpty {
            parts.append("stderr: \(stderrSnippet.prefix(300))")
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
            return ClaudeStructuredOutput(value: decoded, resultEvent: resultEvent)
        } catch {
            throw ClaudeStructuredOutputError.decodingFailed(error, resultEvent: resultEvent)
        }
    }

    public func findResultEvent(in stdout: String, diagnostics: ProcessDiagnostics? = nil) throws -> ClaudeResultEvent {
        let decoder = JSONDecoder()
        var lastResult: ClaudeResultEvent?

        for line in stdout.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }

            let envelope: ClaudeEventEnvelope
            do {
                envelope = try decoder.decode(ClaudeEventEnvelope.self, from: data)
            } catch {
                logger.error("Failed to decode event envelope: \(error.localizedDescription)", metadata: [
                    "line": "\(trimmed.prefix(200))"
                ])
                continue
            }

            guard envelope.type == ClaudeEventType.result else { continue }

            do {
                let event = try decoder.decode(ClaudeResultEvent.self, from: data)
                lastResult = event
            } catch {
                logger.error("Failed to decode result event: \(error.localizedDescription)", metadata: [
                    "line": "\(trimmed.prefix(200))"
                ])
            }
        }

        guard let result = lastResult else {
            throw ClaudeStructuredOutputError.noResultEvent(diagnostics)
        }
        return result
    }
}
