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

    public init(project: ChainProject, enrichedTasks: [EnrichedChainTask]) {
        self.project = project
        self.enrichedTasks = enrichedTasks
        self.actionItems = Self.actionItems(for: enrichedTasks)
    }

    private static func actionItems(for enrichedTasks: [EnrichedChainTask]) -> [ChainActionItem] {
        var items: [ChainActionItem] = []
        for enrichedTask in enrichedTasks {
            guard let pr = enrichedTask.enrichedPR, !pr.isMerged else { continue }
            let n = pr.pr.number
            if pr.isDraft {
                items.append(ChainActionItem(kind: .draftNeedsReview, prNumber: n,
                    message: "PR #\(n) is a draft and needs review promotion"))
            }
            switch pr.buildStatus {
            case .failing(let checks):
                items.append(ChainActionItem(kind: .ciFailure, prNumber: n,
                    message: "PR #\(n) has failing CI: \(checks.joined(separator: ", "))"))
            case .conflicting:
                items.append(ChainActionItem(kind: .mergeConflict, prNumber: n,
                    message: "PR #\(n) has a merge conflict"))
            default:
                break
            }
            if pr.ageDays > 7 && pr.reviewStatus.approvedBy.isEmpty {
                items.append(ChainActionItem(kind: .stalePR, prNumber: n,
                    message: "PR #\(n) has been open for \(pr.ageDays) days with no approvals"))
            }
        }
        return items
    }
}
