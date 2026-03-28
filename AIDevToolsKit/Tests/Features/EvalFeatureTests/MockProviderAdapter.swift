import AIOutputSDK
import EvalSDK
import EvalService
import Foundation
import SkillScannerSDK

struct MockEvalProvider: AIClient, EvalCapable {
    var invocationMethodResult: InvocationMethod?
    var mockCapabilities: ProviderCapabilities
    var result: ProviderResult
    var runHandler: (@Sendable (String) async throws -> EvalRunOutput)?

    var name: String { "claude" }
    var displayName: String { "Mock Claude" }

    init(
        capabilities: ProviderCapabilities = ProviderCapabilities(),
        result: ProviderResult = ProviderResult(provider: Provider(rawValue: "claude"))
    ) {
        self.mockCapabilities = capabilities
        self.result = result
    }

    var evalCapabilities: ProviderCapabilities {
        mockCapabilities
    }

    var streamFormatter: any StreamFormatter {
        MockStreamFormatter()
    }

    func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        AIClientResult(exitCode: 0, stderr: "", stdout: "")
    }

    func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        fatalError("Not implemented in mock")
    }

    func runEval(
        prompt: String,
        outputSchemaPath: URL,
        artifactsDirectory: URL,
        caseId: String,
        model: String?,
        workingDirectory: URL?,
        evalMode: EvalMode,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> EvalRunOutput {
        if let handler = runHandler {
            return try await handler(prompt)
        }
        return EvalRunOutput(result: result, rawStdout: "", stderr: "")
    }

    func invocationMethod(for skillName: String, toolEvents: [ToolEvent], traceCommands: [String], skills: [SkillInfo], repoRoot: URL?) -> InvocationMethod? {
        invocationMethodResult
    }
}

private struct MockStreamFormatter: StreamFormatter {
    func format(_ rawChunk: String) -> String { rawChunk }
}
