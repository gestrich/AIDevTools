import Foundation
import GitHubService
import PRRadarModelsService

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
        let dateString = pr.mergedAt ?? pr.createdAt
        guard let dateString else { return 0 }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return Int(Date().timeIntervalSince(date) / 86400)
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            return Int(Date().timeIntervalSince(date) / 86400)
        }
        return 0
    }
}

public struct PRReviewStatus: Sendable {
    public let approvedBy: [String]
    public let pendingReviewers: [String]

    public init(approvedBy: [String], pendingReviewers: [String]) {
        self.approvedBy = approvedBy
        self.pendingReviewers = pendingReviewers
    }

    public init(reviews: [GitHubReview]) {
        approvedBy = Array(Set(
            reviews.filter { $0.state == .approved }.compactMap { $0.author?.login }
        ))
        pendingReviewers = Array(Set(
            reviews.filter { $0.state == .pending }.compactMap { $0.author?.login }
        ))
    }
}

public enum PRBuildStatus: Sendable {
    case conflicting
    case failing(checks: [String])
    case passing
    case pending(checks: [String])
    case unknown

    public static func from(checkRuns: [GitHubCheckRun], isMergeable: Bool?) -> PRBuildStatus {
        if isMergeable == false { return .conflicting }
        let failing = checkRuns.filter { $0.isFailing }.map { $0.name }
        if !failing.isEmpty { return .failing(checks: failing) }
        let pending = checkRuns.filter { $0.status != .completed }.map { $0.name }
        if !pending.isEmpty { return .pending(checks: pending) }
        return checkRuns.isEmpty ? .unknown : .passing
    }
}

extension ChainProject {
    public func taskHash(for pr: PRRadarModelsService.GitHubPullRequest) -> String? {
        guard let headRefName = pr.headRefName else { return nil }
        if let branchInfo = BranchInfo.fromBranchName(headRefName) {
            return branchInfo.taskHash
        }
        guard let body = pr.body,
              let cursorPath = BranchInfo.sweepCursorPath(fromText: body) else { return nil }
        return tasks.first { $0.description == cursorPath }.map { generateTaskHash($0.description) }
    }
}
