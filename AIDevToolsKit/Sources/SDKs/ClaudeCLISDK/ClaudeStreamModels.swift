import Foundation

public enum ClaudeEventType {
    public static let assistant = "assistant"
    public static let user = "user"
    public static let result = "result"
}

public enum ClaudeContentBlockType {
    public static let toolUse = "tool_use"
}

public enum ClaudeToolName {
    public static let structuredOutput = "StructuredOutput"
    public static let bash = "Bash"
    public static let skill = "Skill"
    public static let read = "Read"
}

public enum ClaudeToolInputKey {
    public static let command = "command"
    public static let skill = "skill"
    public static let filePath = "file_path"
}

public enum ClaudeEnvironmentKey {
    public static let claudeCode = "CLAUDECODE"
}

public struct ClaudeAssistantEvent: Codable, Sendable {
    public let type: String
    public let message: ClaudeMessage?
}

public struct ClaudeMessage: Codable, Sendable {
    public let content: [ClaudeContentBlock]?
}

public enum ClaudeContentBlockType2 {
    public static let text = "text"
    public static let toolResult = "tool_result"
}

public struct ClaudeContentBlock: Codable, Sendable {
    public let type: String
    public let id: String?
    public let text: String?
    public let thinking: String?
    public let name: String?
    public let input: [String: JSONValue]?
    public let content: ToolResultContent?
}

public enum ToolResultContent: Codable, Sendable {
    case string(String)
    case array([[String: JSONValue]])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let arr = try? container.decode([[String: JSONValue]].self) {
            self = .array(arr)
        } else {
            self = .string("")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let str):
            try container.encode(str)
        case .array(let arr):
            try container.encode(arr)
        }
    }

    public var summary: String? {
        switch self {
        case .string(let str):
            return str.isEmpty ? nil : String(str.prefix(200))
        case .array:
            return nil
        }
    }
}

public struct ClaudeUserEvent: Codable, Sendable {
    public let type: String
    public let message: ClaudeUserMessage?
}

public struct ClaudeUserMessage: Codable, Sendable {
    public let content: [ClaudeUserContentBlock]?
}

public struct ClaudeUserContentBlock: Codable, Sendable {
    public let type: String
    public let toolUseId: String?
    public let content: ToolResultContent?
    public let isError: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }
}
