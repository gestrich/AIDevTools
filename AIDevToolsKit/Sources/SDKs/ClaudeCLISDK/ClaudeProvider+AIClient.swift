import AIOutputSDK

extension ClaudeProvider: AIClient {
    public var name: String { "claude" }
    public var displayName: String { "Claude CLI" }

    public func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        var command = Claude(prompt: prompt)
        command.dangerouslySkipPermissions = options.dangerouslySkipPermissions
        command.jsonSchema = options.jsonSchema
        command.model = options.model
        command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
        command.resume = options.sessionId
        command.systemPrompt = options.systemPrompt
        command.verbose = true
        let result = try await run(
            command: command,
            workingDirectory: options.workingDirectory,
            environment: options.environment,
            onFormattedOutput: onOutput,
            onStreamEvent: onStreamEvent
        )
        let sessionId = Self.extractSessionId(from: result.stdout)
        return AIClientResult(exitCode: result.exitCode, sessionId: sessionId, stderr: result.stderr, stdout: result.stdout)
    }

    public func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        var command = Claude(prompt: prompt)
        command.dangerouslySkipPermissions = options.dangerouslySkipPermissions
        command.jsonSchema = jsonSchema
        command.model = options.model
        command.resume = options.sessionId
        command.systemPrompt = options.systemPrompt
        command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
        command.printMode = true
        command.verbose = true
        let output = try await runStructured(
            T.self,
            command: command,
            workingDirectory: options.workingDirectory,
            environment: options.environment,
            onFormattedOutput: onOutput,
            onStreamEvent: onStreamEvent
        )
        let sessionId = Self.extractSessionId(from: output.rawOutput)
        return AIStructuredResult(rawOutput: output.rawOutput, sessionId: sessionId, stderr: output.stderr, value: output.value)
    }
}
