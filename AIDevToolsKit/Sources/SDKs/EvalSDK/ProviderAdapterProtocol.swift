import Foundation
import EvalService
import SkillScannerSDK

public struct RunConfiguration: Sendable {
    public let prompt: String
    public let outputSchemaPath: URL
    public let artifactsDirectory: URL
    public let provider: Provider
    public let caseId: String
    public let model: String?
    public let workingDirectory: URL?
    public let evalMode: EvalMode

    public var providerDirectory: URL {
        OutputService.providerDirectory(artifactsDirectory: artifactsDirectory, provider: provider.rawValue)
    }

    public init(
        prompt: String,
        outputSchemaPath: URL,
        artifactsDirectory: URL,
        provider: Provider,
        caseId: String,
        model: String? = nil,
        workingDirectory: URL? = nil,
        evalMode: EvalMode = .structured
    ) {
        self.prompt = prompt
        self.outputSchemaPath = outputSchemaPath
        self.artifactsDirectory = artifactsDirectory
        self.provider = provider
        self.caseId = caseId
        self.model = model
        self.workingDirectory = workingDirectory
        self.evalMode = evalMode
    }
}

public protocol ProviderAdapterProtocol: Sendable {
    func capabilities() -> ProviderCapabilities
    func run(configuration: RunConfiguration, onOutput: (@Sendable (String) -> Void)?) async throws -> ProviderResult
    func invocationMethod(for skillName: String, toolEvents: [ToolEvent], traceCommands: [String], skills: [SkillInfo], repoRoot: URL?) -> InvocationMethod?
}

extension ProviderAdapterProtocol {
    public func run(configuration: RunConfiguration) async throws -> ProviderResult {
        try await run(configuration: configuration, onOutput: nil)
    }
}
