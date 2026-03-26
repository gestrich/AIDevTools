import Foundation

public struct AIClientOptions: Sendable {
    public var dangerouslySkipPermissions: Bool
    public var environment: [String: String]?
    public var jsonSchema: String?
    public var model: String?
    public var workingDirectory: String?

    public init(
        dangerouslySkipPermissions: Bool = false,
        environment: [String: String]? = nil,
        jsonSchema: String? = nil,
        model: String? = nil,
        workingDirectory: String? = nil
    ) {
        self.dangerouslySkipPermissions = dangerouslySkipPermissions
        self.environment = environment
        self.jsonSchema = jsonSchema
        self.model = model
        self.workingDirectory = workingDirectory
    }
}

public struct AIClientResult: Sendable {
    public let exitCode: Int32
    public let stderr: String
    public let stdout: String

    public init(exitCode: Int32, stderr: String, stdout: String) {
        self.exitCode = exitCode
        self.stderr = stderr
        self.stdout = stdout
    }
}

public struct AIStructuredResult<T: Sendable>: Sendable {
    public let rawOutput: String
    public let stderr: String
    public let value: T

    public init(rawOutput: String, stderr: String, value: T) {
        self.rawOutput = rawOutput
        self.stderr = stderr
        self.value = value
    }
}

public protocol AIClient: Sendable {
    func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> AIClientResult

    func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> AIStructuredResult<T>
}
