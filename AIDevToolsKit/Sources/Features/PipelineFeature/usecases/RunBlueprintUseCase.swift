import PipelineSDK
import UseCaseSDK

public struct RunBlueprintUseCase: UseCase {

    public init() {}

    public func run(
        blueprint: PipelineBlueprint,
        onEvent: @escaping @Sendable (PipelineEvent) -> Void
    ) async throws -> PipelineContext {
        let runner = PipelineRunner()
        return try await runner.run(
            nodes: blueprint.nodes,
            configuration: blueprint.configuration,
            onProgress: onEvent
        )
    }
}
