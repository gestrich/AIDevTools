import Foundation

public struct Pipeline: Sendable {
    public let id: String
    public var steps: [any PipelineStep]
    public var metadata: PipelineMetadata

    public init(id: String, steps: [any PipelineStep], metadata: PipelineMetadata) {
        self.id = id
        self.steps = steps
        self.metadata = metadata
    }
}

public struct PipelineMetadata: Sendable {
    public let name: String
    public let sourceURL: URL?
    public let createdAt: Date

    public init(name: String, sourceURL: URL? = nil, createdAt: Date = Date()) {
        self.name = name
        self.sourceURL = sourceURL
        self.createdAt = createdAt
    }
}
