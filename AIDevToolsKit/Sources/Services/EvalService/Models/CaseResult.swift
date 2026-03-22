import Foundation

public struct CaseResult: Codable, Sendable {
    public let caseId: String
    public var passed: Bool
    public var errors: [String]
    public var skipped: [String]
    public var skillChecks: [SkillCheckResult]
    public var task: String?
    public var input: String?
    public var expected: String?
    public var mustInclude: [String]?
    public var mustNotInclude: [String]?
    public var providerResponse: String?
    public var toolCallSummary: ToolCallSummary?

    public init(
        caseId: String,
        passed: Bool,
        errors: [String] = [],
        skipped: [String] = [],
        skillChecks: [SkillCheckResult] = [],
        task: String? = nil,
        input: String? = nil,
        expected: String? = nil,
        mustInclude: [String]? = nil,
        mustNotInclude: [String]? = nil,
        providerResponse: String? = nil,
        toolCallSummary: ToolCallSummary? = nil
    ) {
        self.caseId = caseId
        self.passed = passed
        self.errors = errors
        self.skipped = skipped
        self.skillChecks = skillChecks
        self.task = task
        self.input = input
        self.expected = expected
        self.mustInclude = mustInclude
        self.mustNotInclude = mustNotInclude
        self.providerResponse = providerResponse
        self.toolCallSummary = toolCallSummary
    }
}

public struct EvalSummary: Codable, Sendable {
    public let provider: String
    public let total: Int
    public let passed: Int
    public let failed: Int
    public let skipped: Int
    public let cases: [CaseResult]

    public init(
        provider: String,
        total: Int,
        passed: Int,
        failed: Int,
        skipped: Int,
        cases: [CaseResult]
    ) {
        self.provider = provider
        self.total = total
        self.passed = passed
        self.failed = failed
        self.skipped = skipped
        self.cases = cases
    }
}
