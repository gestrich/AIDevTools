import Foundation
import CodexCLISDK
import EvalService
import SkillScannerSDK

public struct CodexAdapter: ProviderAdapterProtocol {

    private let codexClient: CodexCLIClient
    private let parser = CodexOutputParser()
    private let outputService = OutputService()

    public init(codexClient: CodexCLIClient = CodexCLIClient()) {
        self.codexClient = codexClient
    }

    public func capabilities() -> ProviderCapabilities {
        ProviderCapabilities(
            supportsToolEventAssertions: true,
            supportsEventStream: true,
            supportsMetrics: false
        )
    }

    public func invocationMethod(for skillName: String, toolEvents: [ToolEvent], traceCommands: [String], skills: [SkillInfo], repoRoot: URL?) -> InvocationMethod? {
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

    public func run(configuration: RunConfiguration, onOutput: (@Sendable (String) -> Void)? = nil) async throws -> ProviderResult {
        let outputFile = configuration.providerDirectory.appendingPathComponent("\(configuration.caseId).json")
        try FileManager.default.createDirectory(at: configuration.providerDirectory, withIntermediateDirectories: true)

        let command = Codex.Exec(
            skipGitRepoCheck: true,
            ephemeral: true,
            outputSchema: configuration.outputSchemaPath.path,
            outputFile: outputFile.path,
            json: true,
            fullAuto: true,
            model: configuration.model,
            prompt: configuration.prompt
        )

        let executionResult = try await codexClient.run(
            command: command,
            workingDirectory: configuration.workingDirectory?.path,
            onFormattedOutput: onOutput
        )

        guard executionResult.isSuccess else {
            let trimmedStderr = executionResult.stderr.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let trimmedStdout = executionResult.stdout.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let errorMessage = trimmedStderr.isEmpty ? trimmedStdout : trimmedStderr
            let errorResult = ProviderResult(
                provider: .codex,
                error: ProviderError(message: errorMessage, subtype: ProviderErrorSubtype.execFailed)
            )
            return try outputService.write(
                result: errorResult,
                stdout: executionResult.stdout,
                stderr: executionResult.stderr,
                configuration: configuration
            )
        }

        var result = parser.buildResult(from: executionResult.stdout)

        do {
            let data = try Data(contentsOf: outputFile)
            let payload = try JSONDecoder().decode([String: JSONValue].self, from: data)
            result.structuredOutput = payload
            result.resultText = payload[StructuredOutputKey.result]?.stringValue ?? ""
        } catch {
            result.error = ProviderError(
                message: "invalid primary output JSON: \(error.localizedDescription)",
                subtype: ProviderErrorSubtype.parseError
            )
        }

        return try outputService.write(
            result: result,
            stdout: executionResult.stdout,
            stderr: executionResult.stderr,
            configuration: configuration
        )
    }

}
