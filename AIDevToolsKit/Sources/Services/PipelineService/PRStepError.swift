import Foundation

public enum PRStepError: LocalizedError, Sendable {
    case commandFailed(command: String, output: String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let output):
            return "'\(command)' failed: \(output.isEmpty ? "(no output)" : output)"
        }
    }
}
