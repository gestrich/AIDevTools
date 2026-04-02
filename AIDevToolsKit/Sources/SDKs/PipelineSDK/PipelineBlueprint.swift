public struct PipelineBlueprint: Sendable {
    public let configuration: PipelineConfiguration
    public let initialNodeManifest: [NodeManifest]
    public let nodes: [any PipelineNode]

    public init(
        nodes: [any PipelineNode],
        configuration: PipelineConfiguration,
        initialNodeManifest: [NodeManifest]
    ) {
        self.configuration = configuration
        self.initialNodeManifest = initialNodeManifest
        self.nodes = nodes
    }
}
