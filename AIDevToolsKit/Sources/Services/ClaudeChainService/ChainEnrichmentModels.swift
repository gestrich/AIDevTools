import Foundation

public struct EnrichedChainTask: Sendable {
    public let task: ChainTask
    public let enrichedPR: EnrichedPR?

    public init(task: ChainTask, enrichedPR: EnrichedPR? = nil) {
        self.task = task
        self.enrichedPR = enrichedPR
    }
}

public enum ChainActionKind: Sendable {
    case ciFailure
    case draftNeedsReview
    case mergeConflict
    case needsReviewers
    case stalePR
}

public struct ChainActionItem: Identifiable, Sendable {
    public var id: String { "\(prNumber)-\(kind)" }
    public let kind: ChainActionKind
    public let message: String
    public let prNumber: Int

    public init(kind: ChainActionKind, prNumber: Int, message: String) {
        self.kind = kind
        self.prNumber = prNumber
        self.message = message
    }
}

public struct ChainProjectDetail: Sendable {
    public let actionItems: [ChainActionItem]
    public let enrichedTasks: [EnrichedChainTask]
    public let project: ChainProject

    public init(project: ChainProject, enrichedTasks: [EnrichedChainTask], actionItems: [ChainActionItem]) {
        self.actionItems = actionItems
        self.enrichedTasks = enrichedTasks
        self.project = project
    }
}
