import AIOutputSDK
import Foundation

public struct SkillAssertion: Codable, Sendable {
    public let skill: String
    public let shouldTrigger: Bool?
    public let mustBeInvoked: Bool?
    public let mustNotBeInvoked: Bool?

    public init(
        skill: String,
        shouldTrigger: Bool? = nil,
        mustBeInvoked: Bool? = nil,
        mustNotBeInvoked: Bool? = nil
    ) {
        self.skill = skill
        self.shouldTrigger = shouldTrigger
        self.mustBeInvoked = mustBeInvoked
        self.mustNotBeInvoked = mustNotBeInvoked
    }
}

public struct EvalCase: Codable, Sendable {
    public let id: String
    public let suite: String?
    public let mode: EvalMode
    public let skills: [SkillAssertion]?
    public let task: String?
    public let input: String?
    public let prompt: String?
    public let expected: String?
    public let mustInclude: [String]?
    public let mustNotInclude: [String]?
    public let deterministic: DeterministicChecks?
    public let rubric: RubricConfig?

    public init(
        id: String,
        suite: String? = nil,
        mode: EvalMode = .structured,
        skills: [SkillAssertion]? = nil,
        task: String? = nil,
        input: String? = nil,
        prompt: String? = nil,
        expected: String? = nil,
        mustInclude: [String]? = nil,
        mustNotInclude: [String]? = nil,
        deterministic: DeterministicChecks? = nil,
        rubric: RubricConfig? = nil
    ) {
        self.id = id
        self.suite = suite
        self.mode = mode
        self.skills = skills
        self.task = task
        self.input = input
        self.prompt = prompt
        self.expected = expected
        self.mustInclude = mustInclude
        self.mustNotInclude = mustNotInclude
        self.deterministic = deterministic
        self.rubric = rubric
    }

    public func withSuite(_ suite: String) -> EvalCase {
        EvalCase(
            id: id,
            suite: suite,
            mode: mode,
            skills: skills,
            task: task,
            input: input,
            prompt: prompt,
            expected: expected,
            mustInclude: mustInclude,
            mustNotInclude: mustNotInclude,
            deterministic: deterministic,
            rubric: rubric
        )
    }

    public var qualifiedId: String {
        "\(suite ?? "unknown").\(id)"
    }

    public var summaryDescription: String {
        var lines = ["\(qualifiedId)  mode: \(mode.rawValue)"]
        if let skills, !skills.isEmpty {
            let skillNames = skills.map(\.skill).joined(separator: ", ")
            lines.append("  skills: \(skillNames)")
        }
        if let task { lines.append("  task: \(task)") }
        if let input { lines.append("  input: \(input)") }
        if let prompt { lines.append("  prompt: \(prompt)") }
        if let expected { lines.append("  expected: \(expected)") }
        if let mustInclude, !mustInclude.isEmpty {
            lines.append("  must_include: \(mustInclude.joined(separator: ", "))")
        }
        if let mustNotInclude, !mustNotInclude.isEmpty {
            lines.append("  must_not_include: \(mustNotInclude.joined(separator: ", "))")
        }
        if deterministic != nil { lines.append("  deterministic: yes") }
        if rubric != nil { lines.append("  rubric: yes") }
        return lines.joined(separator: "\n")
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        suite = try container.decodeIfPresent(String.self, forKey: .suite)
        mode = try container.decodeIfPresent(EvalMode.self, forKey: .mode) ?? .structured
        skills = try container.decodeIfPresent([SkillAssertion].self, forKey: .skills)
        task = try container.decodeIfPresent(String.self, forKey: .task)
        input = try container.decodeIfPresent(String.self, forKey: .input)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        expected = try container.decodeIfPresent(String.self, forKey: .expected)
        mustInclude = try container.decodeIfPresent([String].self, forKey: .mustInclude)
        mustNotInclude = try container.decodeIfPresent([String].self, forKey: .mustNotInclude)
        deterministic = try container.decodeIfPresent(DeterministicChecks.self, forKey: .deterministic)
        rubric = try container.decodeIfPresent(RubricConfig.self, forKey: .rubric)
    }
}

public struct DeterministicChecks: Codable, Sendable {
    public let traceCommandContains: [String]?
    public let traceCommandNotContains: [String]?
    public let traceCommandOrder: [String]?
    public let maxCommands: Int?
    public let maxRepeatedCommands: Int?
    public let filesExist: [String]?
    public let filesNotExist: [String]?
    public let fileContains: [String: [String]]?
    public let fileNotContains: [String: [String]]?
    public let expectedDiff: ExpectedDiff?
    public let referenceFileMustBeRead: [String]?
    public let referenceFileMustNotBeRead: [String]?

    public init(
        traceCommandContains: [String]? = nil,
        traceCommandNotContains: [String]? = nil,
        traceCommandOrder: [String]? = nil,
        maxCommands: Int? = nil,
        maxRepeatedCommands: Int? = nil,
        filesExist: [String]? = nil,
        filesNotExist: [String]? = nil,
        fileContains: [String: [String]]? = nil,
        fileNotContains: [String: [String]]? = nil,
        expectedDiff: ExpectedDiff? = nil,
        referenceFileMustBeRead: [String]? = nil,
        referenceFileMustNotBeRead: [String]? = nil
    ) {
        self.traceCommandContains = traceCommandContains
        self.traceCommandNotContains = traceCommandNotContains
        self.traceCommandOrder = traceCommandOrder
        self.maxCommands = maxCommands
        self.maxRepeatedCommands = maxRepeatedCommands
        self.filesExist = filesExist
        self.filesNotExist = filesNotExist
        self.fileContains = fileContains
        self.fileNotContains = fileNotContains
        self.expectedDiff = expectedDiff
        self.referenceFileMustBeRead = referenceFileMustBeRead
        self.referenceFileMustNotBeRead = referenceFileMustNotBeRead
    }
}

public struct ExpectedDiff: Codable, Sendable {
    public let noDiff: Bool?
    public let contains: [String]?
    public let notContains: [String]?

    public init(
        noDiff: Bool? = nil,
        contains: [String]? = nil,
        notContains: [String]? = nil
    ) {
        self.noDiff = noDiff
        self.contains = contains
        self.notContains = notContains
    }
}

public struct RubricConfig: Codable, Sendable {
    public let prompt: String
    public let requireOverallPass: Bool?
    public let minScore: Int?
    public let requiredCheckIds: [String]?
    public let schemaPath: String?

    public init(
        prompt: String,
        requireOverallPass: Bool? = nil,
        minScore: Int? = nil,
        requiredCheckIds: [String]? = nil,
        schemaPath: String? = nil
    ) {
        self.prompt = prompt
        self.requireOverallPass = requireOverallPass
        self.minScore = minScore
        self.requiredCheckIds = requiredCheckIds
        self.schemaPath = schemaPath
    }
}
