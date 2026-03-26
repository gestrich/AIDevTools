import AIOutputSDK
import Foundation

extension CodexCLIClient: AIClient {
    public func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> AIClientResult {
        var command = Codex.Exec(prompt: prompt)
        command.fullAuto = options.dangerouslySkipPermissions
        command.model = options.model
        if let jsonSchema = options.jsonSchema {
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

    public func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        var command = Codex.Exec(prompt: prompt)
        command.fullAuto = options.dangerouslySkipPermissions
        command.json = true
        command.model = options.model
        command.outputSchema = jsonSchema
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
}
