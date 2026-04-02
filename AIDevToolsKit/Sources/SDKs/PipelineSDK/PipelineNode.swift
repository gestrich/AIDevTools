import AIOutputSDK

public protocol PipelineNode: Sendable {
    var id: String { get }
    var displayName: String { get }

    func run(
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineNodeProgress) -> Void
    ) async throws -> PipelineContext
}

public enum PipelineNodeProgress: Sendable {
    case output(String)
    case pausedForReview
    case custom(String)
    case streamEvent(AIStreamEvent)
}
