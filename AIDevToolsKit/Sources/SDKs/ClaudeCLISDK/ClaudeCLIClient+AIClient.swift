import AIOutputSDK

extension ClaudeCLIClient: AIClient {
    public func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> AIClientResult {
        var command = Claude(prompt: prompt)
        command.dangerouslySkipPermissions = options.dangerouslySkipPermissions
        command.model = options.model
        if let jsonSchema = options.jsonSchema {
            command.jsonSchema = jsonSchema
            command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
            command.printMode = true
            command.verbose = true
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
        var command = Claude(prompt: prompt)
        command.dangerouslySkipPermissions = options.dangerouslySkipPermissions
        command.jsonSchema = jsonSchema
        command.model = options.model
        command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
        command.printMode = true
        command.verbose = true
        let output = try await runStructured(
            T.self,
            command: command,
            workingDirectory: options.workingDirectory,
            environment: options.environment,
            onFormattedOutput: onOutput
        )
        return AIStructuredResult(rawOutput: output.rawOutput, stderr: output.stderr, value: output.value)
    }
}
