import Foundation

public struct EnrichedChainTask: Sendable {
    public let task: ChainTask
    public let enrichedPR: EnrichedPR?

    public init(task: ChainTask, enrichedPR: EnrichedPR? = nil) {
        self.task = task
        self.enrichedPR = enrichedPR
    }
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

public enum ChainActionKind: Sendable {
    case ciFailure
    case draftNeedsReview
    case mergeConflict
    case stalePR
}

public struct ChainProjectDetail: Sendable {
    public let actionItems: [ChainActionItem]
    public let enrichedTasks: [EnrichedChainTask]
    public let project: ChainProject

    public var actionPRCount: Int {
        Set(actionItems.map { $0.prNumber }).count
    }

    public var openPRCount: Int {
        enrichedTasks.filter { task in
            guard let pr = task.enrichedPR else { return false }
            return !pr.isMerged
        }.count
    }

    public init(project: ChainProject, enrichedTasks: [EnrichedChainTask], actionItems: [ChainActionItem]) {
        self.actionItems = actionItems
        self.enrichedTasks = enrichedTasks
        self.project = project
    }
}
