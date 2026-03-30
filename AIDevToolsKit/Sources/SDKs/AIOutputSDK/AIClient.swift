import Foundation

public struct AIClientOptions: Sendable {
    public var dangerouslySkipPermissions: Bool
    public var environment: [String: String]?
    public var jsonSchema: String?
    public var mcpConfigPath: String?
    public var model: String?
    public var sessionId: String?
    public var systemPrompt: String?
    public var workingDirectory: String?

    public init(
        dangerouslySkipPermissions: Bool = false,
        environment: [String: String]? = nil,
        jsonSchema: String? = nil,
        mcpConfigPath: String? = nil,
        model: String? = nil,
        sessionId: String? = nil,
        systemPrompt: String? = nil,
        workingDirectory: String? = nil
    ) {
        self.dangerouslySkipPermissions = dangerouslySkipPermissions
        self.environment = environment
        self.jsonSchema = jsonSchema
        self.mcpConfigPath = mcpConfigPath
        self.model = model
        self.sessionId = sessionId
        self.systemPrompt = systemPrompt
        self.workingDirectory = workingDirectory
    }
}

public struct AIClientResult: Sendable {
    public let exitCode: Int32
    public let sessionId: String?
    public let stderr: String
    public let stdout: String

    public init(exitCode: Int32, sessionId: String? = nil, stderr: String, stdout: String) {
        self.exitCode = exitCode
        self.sessionId = sessionId
        self.stderr = stderr
        self.stdout = stdout
    }
}

public struct AIStructuredResult<T: Sendable>: Sendable {
    public let rawOutput: String
    public let sessionId: String?
    public let stderr: String
    public let value: T

    public init(rawOutput: String, sessionId: String? = nil, stderr: String, value: T) {
        self.rawOutput = rawOutput
        self.sessionId = sessionId
        self.stderr = stderr
        self.value = value
    }
}

public protocol AIClient: Sendable {
    var name: String { get }
    var displayName: String { get }

    func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult

    func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIStructuredResult<T>

    func listSessions(workingDirectory: String) async -> [ChatSession]
    func loadSessionMessages(sessionId: String, workingDirectory: String) async -> [ChatSessionMessage]
    func getSessionDetails(sessionId: String, summary: String, lastModified: Date, workingDirectory: String) -> SessionDetails?
}

extension AIClient {
    /// Returns a new independent instance of this client with its own underlying resources.
    /// CLI-based providers override this to return a fresh instance with its own CLIClient actor,
    /// preventing serialization of concurrent calls (e.g., plan execution vs. interactive chat).
    public func makeIndependentCopy() -> any AIClient { self }

    public func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> AIClientResult {
        try await run(prompt: prompt, options: options, onOutput: onOutput, onStreamEvent: nil)
    }

    public func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        try await runStructured(type, prompt: prompt, jsonSchema: jsonSchema, options: options, onOutput: onOutput, onStreamEvent: nil)
    }

    public func listSessions(workingDirectory: String) async -> [ChatSession] { [] }
    public func loadSessionMessages(sessionId: String, workingDirectory: String) async -> [ChatSessionMessage] { [] }
    public func getSessionDetails(sessionId: String, summary: String, lastModified: Date, workingDirectory: String) -> SessionDetails? { nil }
}
