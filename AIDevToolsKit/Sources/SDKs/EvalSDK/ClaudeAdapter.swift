import AIOutputSDK
import EvalService
import Foundation
import SkillScannerSDK

public struct ClaudeAdapter: ProviderAdapterProtocol {

    private let client: any AIClient
    private let parser = ClaudeOutputParser()
    private let outputService = OutputService()
    private let debug: Bool

    public init(client: any AIClient, debug: Bool = false) {
        self.client = client
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

        let options = AIClientOptions(
            dangerouslySkipPermissions: configuration.evalMode == .edit,
            jsonSchema: schemaJSON,
            model: configuration.model,
            workingDirectory: configuration.workingDirectory?.path
        )

        let session = OutputService.makeSession(
            artifactsDirectory: configuration.artifactsDirectory,
            provider: configuration.provider.rawValue,
            caseId: configuration.caseId,
            client: client
        )

        let result = try await session.run(
            prompt: configuration.prompt,
            options: options,
            onOutput: onOutput
        )

        if debug {
            print("[DEBUG] Exit code: \(result.exitCode)")
            print("[DEBUG] Stderr: \(result.stderr)")
            print("[DEBUG] Stdout (first 500 chars): \(String(result.stdout.prefix(500)))")
        }

        let providerResult = parser.buildResult(from: result.stdout)
        return try outputService.writeArtifacts(
            result: providerResult,
            stderr: result.stderr,
            session: session,
            configuration: configuration
        )
    }

}
