import Foundation

public enum CodexEventItemType {
    public static let commandExecution = "command_execution"
}

public enum CodexStreamEventType {
    public static let itemCompleted = "item.completed"
}

public struct CodexStreamEvent: Codable, Sendable {
    public let type: String?
    public let item: CodexEventItem?
}

public struct CodexEventItem: Codable, Sendable {
    public let type: String
    public let command: String?
    public let aggregatedOutput: String?
    public let exitCode: Int?

    enum CodingKeys: String, CodingKey {
        case type, command
        case aggregatedOutput = "aggregated_output"
        case exitCode = "exit_code"
    }
}
