import Foundation
import CLISDK
import ClaudeCLISDK
import EvalService
import SkillScannerSDK

public struct ClaudeAdapter: ProviderAdapterProtocol {

    private let claudeClient: ClaudeCLIClient
    private let parser = ClaudeOutputParser()
    private let outputService = OutputService()
    private let debug: Bool

    public init(client: CLIClient = CLIClient(), debug: Bool = false) {
        self.claudeClient = ClaudeCLIClient(client: client)
        self.debug = debug
    }

    public func capabilities() -> ProviderCapabilities {
        ProviderCapabilities(
            supportsToolEventAssertions: true,
            supportsEventStream: true,
            supportsMetrics: true
        )
    }

    public func invocationMethod(for skillName: String, toolEvents: [ToolEvent], traceCommands: [String], skills: [SkillInfo], repoRoot: URL?) -> InvocationMethod? {
        if toolEvents.contains(where: { $0.skillName == skillName }) { return .explicit }
        let prefixes = [".claude/skills/", ".agents/skills/"]
        let filePaths = toolEvents.compactMap(\.filePath)
        let matches = filePaths.contains { path in
            prefixes.contains { prefix in
                guard path.contains(prefix) else { return false }
                return path.contains("/\(skillName)/") || path.contains("/\(skillName).md")
            }
        }
        return matches ? .discovered : nil
    }

    public func run(configuration: RunConfiguration, onOutput: (@Sendable (String) -> Void)? = nil) async throws -> ProviderResult {
        try FileManager.default.createDirectory(
            at: configuration.providerDirectory,
            withIntermediateDirectories: true
        )

        let schemaData = try Data(contentsOf: configuration.outputSchemaPath)
        let schemaObject = try JSONSerialization.jsonObject(with: schemaData)
        let compactData = try JSONSerialization.data(withJSONObject: schemaObject, options: [.sortedKeys])
        let schemaJSON = String(data: compactData, encoding: .utf8) ?? ""

        var command = Claude(prompt: configuration.prompt)
        command.printMode = true
        command.dangerouslySkipPermissions = configuration.evalMode == .edit
        command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
        command.jsonSchema = schemaJSON
        command.verbose = true
        command.model = configuration.model

        if debug {
            print("[DEBUG] Claude command arguments:")
            for (i, arg) in command.commandArguments.enumerated() {
                print("  [\(i)]: \(arg.debugDescription)")
            }
        }

        let executionResult = try await claudeClient.run(
            command: command,
            workingDirectory: configuration.workingDirectory?.path,
            onFormattedOutput: onOutput
        )

        if debug {
            print("[DEBUG] Exit code: \(executionResult.exitCode)")
            print("[DEBUG] Stderr: \(executionResult.stderr)")
            print("[DEBUG] Stdout (first 500 chars): \(String(executionResult.stdout.prefix(500)))")
        }

        let result = parser.buildResult(from: executionResult.stdout)
        return try outputService.write(
            result: result,
            stdout: executionResult.stdout,
            stderr: executionResult.stderr,
            configuration: configuration
        )
    }

}
