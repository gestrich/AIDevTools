public struct TaskSourceNode: PipelineNode {
    public let displayName: String
    public let id: String
    private let source: any TaskSource

    public init(id: String, displayName: String, source: any TaskSource) {
        self.displayName = displayName
        self.id = id
        self.source = source
    }

    public func run(
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineNodeProgress) -> Void
    ) async throws -> PipelineContext {
        var updated = context
        updated[PipelineContext.injectedTaskSourceKey] = source
        return updated
    }
}
