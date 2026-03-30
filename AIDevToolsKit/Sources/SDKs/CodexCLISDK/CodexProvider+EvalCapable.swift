import AIOutputSDK
import Foundation
import SkillScannerSDK

extension CodexProvider: EvalCapable {

    public var evalCapabilities: ProviderCapabilities {
        ProviderCapabilities(
            supportsToolEventAssertions: true,
            supportsEventStream: true,
            supportsMetrics: false
        )
    }

    public var streamFormatter: any StreamFormatter {
        CodexStreamFormatter()
    }

    public func invocationMethod(
        for skillName: String,
        toolEvents: [ToolEvent],
        traceCommands: [String],
        skills: [SkillInfo],
        repoRoot: URL?
    ) -> InvocationMethod? {
        if let skillInfo = skills.first(where: { $0.name == skillName }), let repoRoot {
            let relativePath = skillInfo.relativePath(to: repoRoot)
            if traceCommands.contains(where: { $0.contains(relativePath) }) { return .inferred }
        }
        let prefixes = [".claude/skills/", ".agents/skills/"]
        let matches = traceCommands.contains { cmd in
            prefixes.contains { prefix in
                guard cmd.contains(prefix) else { return false }
                return cmd.contains("/\(skillName)/") || cmd.contains("/\(skillName).md")
            }
        }
        return matches ? .inferred : nil
    }

    public func runEval(
        prompt: String,
        outputSchemaPath: URL,
        artifactsDirectory: URL,
        caseId: String,
        model: String?,
        workingDirectory: URL?,
        evalMode: EvalMode,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> EvalRunOutput {
        let providerDir = artifactsDirectory.appendingPathComponent(name)
        let outputFile = providerDir.appendingPathComponent("\(caseId).json")
        try FileManager.default.createDirectory(at: providerDir, withIntermediateDirectories: true)

        let options = AIClientOptions(
            dangerouslySkipPermissions: true,
            environment: [
                Self.outputFileEnvironmentKey: outputFile.path,
                Self.outputSchemaPathEnvironmentKey: outputSchemaPath.path,
            ],
            model: model,
            workingDirectory: workingDirectory?.path
        )

        let result = try await run(prompt: prompt, options: options, onOutput: onOutput)

        guard result.exitCode == 0 else {
            let trimmedStderr = result.stderr.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let trimmedStdout = result.stdout.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let errorMessage = trimmedStderr.isEmpty ? trimmedStdout : trimmedStderr
            let errorResult = ProviderResult(
                provider: Provider(client: self),
                error: ProviderError(message: errorMessage, subtype: ProviderErrorSubtype.execFailed)
            )
            return EvalRunOutput(result: errorResult, rawStdout: result.stdout, stderr: result.stderr)
        }

        let baseResult = CodexOutputParser().buildResult(from: result.stdout, provider: Provider(client: self))

        let finalResult: ProviderResult
        do {
            let data = try Data(contentsOf: outputFile)
            let payload = try JSONDecoder().decode([String: JSONValue].self, from: data)
            finalResult = ProviderResult(
                provider: baseResult.provider,
                structuredOutput: payload,
                resultText: payload[StructuredOutputKey.result]?.stringValue ?? "",
                events: baseResult.events,
                toolEvents: baseResult.toolEvents,
                metrics: baseResult.metrics,
                rawStdoutPath: baseResult.rawStdoutPath,
                rawStderrPath: baseResult.rawStderrPath,
                rawTracePath: baseResult.rawTracePath,
                error: baseResult.error,
                toolCallSummary: baseResult.toolCallSummary
            )
        } catch {
            finalResult = ProviderResult(
                provider: baseResult.provider,
                structuredOutput: baseResult.structuredOutput,
                resultText: baseResult.resultText,
                events: baseResult.events,
                toolEvents: baseResult.toolEvents,
                metrics: baseResult.metrics,
                rawStdoutPath: baseResult.rawStdoutPath,
                rawStderrPath: baseResult.rawStderrPath,
                rawTracePath: baseResult.rawTracePath,
                error: ProviderError(
                    message: "invalid primary output JSON: \(error.localizedDescription)",
                    subtype: ProviderErrorSubtype.parseError
                ),
                toolCallSummary: baseResult.toolCallSummary
            )
        }

        return EvalRunOutput(result: finalResult, rawStdout: result.stdout, stderr: result.stderr)
    }
}
