import Foundation
import SkillScannerSDK

public enum Provider: String, Codable, Sendable, CaseIterable {
    case codex
    case claude
}

/// How a skill invocation was detected during eval grading.
public enum InvocationMethod: String, Codable, Sendable {
    /// The AI used a dedicated Skill tool to invoke the skill (Claude only).
    case explicit
    /// The skill file was read without using the Skill tool — found during exploration.
    case discovered
    /// The provider lacks a dedicated skill tool, so invocation is inferred from
    /// the skill file appearing in trace commands. Cannot confirm intent.
    case inferred
}

/// Result of a skill invocation check during eval grading.
public enum SkillCheckResult: Sendable {
    case invoked(SkillInfo, method: InvocationMethod)
    case notInvoked(skillName: String)
    case skipped(skillName: String, reason: String)

    public var displayDescription: String {
        switch self {
        case .invoked(let skill, let method):
            var desc = "skill '\(skill.name)' invoked (\(method.rawValue))"
            if method == .inferred {
                desc += " — provider lacks dedicated skill tool; invocation inferred from file read"
            }
            return desc
        case .notInvoked(let name):
            return "skill '\(name)' not invoked"
        case .skipped(let name, let reason):
            return "skill '\(name)' check skipped: \(reason)"
        }
    }
}

extension SkillCheckResult: Codable {
    private enum CodingKeys: String, CodingKey {
        case status, skill, method, skillName, reason
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .invoked(let skill, let method):
            try container.encode("invoked", forKey: .status)
            try container.encode(skill, forKey: .skill)
            try container.encode(method, forKey: .method)
        case .notInvoked(let name):
            try container.encode("notInvoked", forKey: .status)
            try container.encode(name, forKey: .skillName)
        case .skipped(let name, let reason):
            try container.encode("skipped", forKey: .status)
            try container.encode(name, forKey: .skillName)
            try container.encode(reason, forKey: .reason)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)
        switch status {
        case "invoked":
            let skill = try container.decode(SkillInfo.self, forKey: .skill)
            let method = try container.decode(InvocationMethod.self, forKey: .method)
            self = .invoked(skill, method: method)
        case "notInvoked":
            let name = try container.decode(String.self, forKey: .skillName)
            self = .notInvoked(skillName: name)
        case "skipped":
            let name = try container.decode(String.self, forKey: .skillName)
            let reason = try container.decode(String.self, forKey: .reason)
            self = .skipped(skillName: name, reason: reason)
        default:
            throw DecodingError.dataCorruptedError(forKey: .status, in: container, debugDescription: "Unknown status: \(status)")
        }
    }
}

public struct ToolEvent: Sendable, Equatable {
    public let name: String
    public var inputKeys: [String]
    public var command: String?
    public var output: String?
    public var exitCode: Int?
    public var skillName: String?
    public var filePath: String?

    public init(
        name: String,
        inputKeys: [String] = [],
        command: String? = nil,
        output: String? = nil,
        exitCode: Int? = nil,
        skillName: String? = nil,
        filePath: String? = nil
    ) {
        self.name = name
        self.inputKeys = inputKeys
        self.command = command
        self.output = output
        self.exitCode = exitCode
        self.skillName = skillName
        self.filePath = filePath
    }
}

public struct ToolCallSummary: Codable, Sendable, Equatable {
    public var attempted: Int
    public var succeeded: Int
    public var rejected: Int
    public var errored: Int

    public init(attempted: Int = 0, succeeded: Int = 0, rejected: Int = 0, errored: Int = 0) {
        self.attempted = attempted
        self.succeeded = succeeded
        self.rejected = rejected
        self.errored = errored
    }
}

public struct ProviderError: Sendable {
    public let message: String
    public var subtype: String?
    public var details: [String: JSONValue]?

    public init(
        message: String,
        subtype: String? = nil,
        details: [String: JSONValue]? = nil
    ) {
        self.message = message
        self.subtype = subtype
        self.details = details
    }
}

public struct ProviderMetrics: Sendable {
    public var durationMs: Int?
    public var costUsd: Double?
    public var turns: Int?

    public init(
        durationMs: Int? = nil,
        costUsd: Double? = nil,
        turns: Int? = nil
    ) {
        self.durationMs = durationMs
        self.costUsd = costUsd
        self.turns = turns
    }
}

public struct ProviderCapabilities: Sendable {
    public var supportsToolEventAssertions: Bool
    public var supportsEventStream: Bool
    public var supportsMetrics: Bool

    public init(
        supportsToolEventAssertions: Bool = true,
        supportsEventStream: Bool = true,
        supportsMetrics: Bool = false
    ) {
        self.supportsToolEventAssertions = supportsToolEventAssertions
        self.supportsEventStream = supportsEventStream
        self.supportsMetrics = supportsMetrics
    }
}

public struct ProviderResult: Sendable {
    public let provider: Provider
    public var structuredOutput: [String: JSONValue]?
    public var resultText: String?
    public var events: [[String: JSONValue]]
    public var toolEvents: [ToolEvent]
    public var metrics: ProviderMetrics?
    public var rawStdoutPath: URL?
    public var rawStderrPath: URL?
    public var rawTracePath: URL?
    public var error: ProviderError?
    public var toolCallSummary: ToolCallSummary?

    public init(
        provider: Provider,
        structuredOutput: [String: JSONValue]? = nil,
        resultText: String? = nil,
        events: [[String: JSONValue]] = [],
        toolEvents: [ToolEvent] = [],
        metrics: ProviderMetrics? = nil,
        rawStdoutPath: URL? = nil,
        rawStderrPath: URL? = nil,
        rawTracePath: URL? = nil,
        error: ProviderError? = nil,
        toolCallSummary: ToolCallSummary? = nil
    ) {
        self.provider = provider
        self.structuredOutput = structuredOutput
        self.resultText = resultText
        self.events = events
        self.toolEvents = toolEvents
        self.metrics = metrics
        self.rawStdoutPath = rawStdoutPath
        self.rawStderrPath = rawStderrPath
        self.rawTracePath = rawTracePath
        self.error = error
        self.toolCallSummary = toolCallSummary
    }
}
