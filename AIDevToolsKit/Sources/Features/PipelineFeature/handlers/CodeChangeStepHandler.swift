import AIOutputSDK
import PipelineSDK

public struct CodeChangeStepHandler: StepHandler {
    private let client: any AIClient
    private let onOutput: (@Sendable (String) -> Void)?

    public init(client: any AIClient, onOutput: (@Sendable (String) -> Void)? = nil) {
        self.client = client
        self.onOutput = onOutput
    }

    public func execute(_ step: CodeChangeStep, context: PipelineContext) async throws -> [any PipelineStep] {
        let options = AIClientOptions(
            dangerouslySkipPermissions: true,
            workingDirectory: context.workingDirectory
        )
        _ = try await client.run(
            prompt: step.prompt,
            options: options,
            onOutput: onOutput
        )
        return []
    }
}
