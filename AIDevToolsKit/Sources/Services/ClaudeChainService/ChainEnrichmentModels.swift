import Foundation
import PRRadarModelsService

public struct PRReviewStatus: Sendable {
    public let approvedBy: [String]
    public let pendingReviewers: [String]

    public init(approvedBy: [String], pendingReviewers: [String]) {
        self.approvedBy = approvedBy
        self.pendingReviewers = pendingReviewers
    }
}

public enum PRBuildStatus: Sendable {
    case passing
    case failing(checks: [String])
    case pending(checks: [String])
    case conflicting
    case unknown
}

public struct EnrichedPR: Sendable {
    public let pr: PRRadarModelsService.GitHubPullRequest
    public let isDraft: Bool
    public let reviewStatus: PRReviewStatus
    public let buildStatus: PRBuildStatus

    public init(
        pr: PRRadarModelsService.GitHubPullRequest,
        reviewStatus: PRReviewStatus,
        buildStatus: PRBuildStatus
    ) {
        self.pr = pr
        self.isDraft = pr.isDraft
        self.reviewStatus = reviewStatus
        self.buildStatus = buildStatus
    }

    public var isMerged: Bool { pr.mergedAt != nil }

    public var ageDays: Int {
        guard let createdAtString = pr.createdAt else { return 0 }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: createdAtString) {
            return Int(Date().timeIntervalSince(date) / 86400)
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: createdAtString) {
            return Int(Date().timeIntervalSince(date) / 86400)
        }
        return 0
    }
}

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

public struct ChainActionItem: Sendable {
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
