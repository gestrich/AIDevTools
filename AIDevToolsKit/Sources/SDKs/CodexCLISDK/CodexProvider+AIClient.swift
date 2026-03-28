import AIOutputSDK
import Foundation

extension CodexProvider: AIClient, SessionListable {
    public var name: String { "codex" }
    public var displayName: String { "Codex CLI" }

    public static let outputFileEnvironmentKey = "CODEX_OUTPUT_FILE"
    public static let outputSchemaPathEnvironmentKey = "CODEX_OUTPUT_SCHEMA_PATH"

    public func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        if let sessionId = options.sessionId {
            return try await runResume(sessionId: sessionId, prompt: prompt, options: options, onOutput: onOutput)
        }

        var command = Codex.Exec(prompt: prompt)
        command.ephemeral = true
        command.fullAuto = options.dangerouslySkipPermissions
        command.model = options.model
        command.skipGitRepoCheck = true
        if let outputFile = options.environment?[Self.outputFileEnvironmentKey] {
            command.outputFile = outputFile
        }
        if let schemaPath = options.environment?[Self.outputSchemaPathEnvironmentKey] {
            command.json = true
            command.outputSchema = schemaPath
        } else if let jsonSchema = options.jsonSchema {
            command.json = true
            command.outputSchema = jsonSchema
        }
        let result = try await run(
            command: command,
            workingDirectory: options.workingDirectory,
            environment: options.environment,
            onFormattedOutput: onOutput
        )
        return AIClientResult(exitCode: result.exitCode, stderr: result.stderr, stdout: result.stdout)
    }

    private func runResume(
        sessionId: String,
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> AIClientResult {
        var command = Codex.Exec.Resume(sessionId: sessionId, prompt: prompt)
        command.fullAuto = options.dangerouslySkipPermissions
        command.model = options.model
        let result = try await run(
            command: command,
            workingDirectory: options.workingDirectory,
            environment: options.environment,
            onFormattedOutput: onOutput
        )
        return AIClientResult(exitCode: result.exitCode, sessionId: sessionId, stderr: result.stderr, stdout: result.stdout)
    }

    public func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        var command = Codex.Exec(prompt: prompt)
        command.ephemeral = true
        command.fullAuto = options.dangerouslySkipPermissions
        command.json = true
        command.model = options.model
        command.outputSchema = jsonSchema
        command.skipGitRepoCheck = true
        let result = try await run(
            command: command,
            workingDirectory: options.workingDirectory,
            environment: options.environment,
            onFormattedOutput: onOutput
        )
        let data = Data(result.stdout.utf8)
        let value = try JSONDecoder().decode(T.self, from: data)
        return AIStructuredResult(rawOutput: result.stdout, stderr: result.stderr, value: value)
    }

    // MARK: - SessionListable

    public func listSessions(workingDirectory: String) async -> [ChatSession] {
        CodexSessionStorage().listSessions()
    }

    public func loadSessionMessages(sessionId: String, workingDirectory: String) async -> [ChatSessionMessage] {
        CodexSessionStorage().loadMessages(sessionId: sessionId)
    }
}
