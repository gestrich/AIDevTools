import ClaudeChainService
import Foundation
import GitHubService
import PRRadarModelsService
import UseCaseSDK

private let claudeChainBranchPrefix = "claude-chain-"

public struct GetChainDetailUseCase: UseCase {

    public struct Options: Sendable {
        public let projectName: String
        public let repoPath: URL

        public init(repoPath: URL, projectName: String) {
            self.projectName = projectName
            self.repoPath = repoPath
        }
    }

    private let gitHubPRService: any GitHubPRServiceProtocol

    public init(gitHubPRService: any GitHubPRServiceProtocol) {
        self.gitHubPRService = gitHubPRService
    }

    // MARK: - Cache-first load (no network)

    /// Returns a `ChainProjectDetail` built entirely from disk cache, or `nil` if no index exists yet.
    public func loadCached(options: Options) async throws -> ChainProjectDetail? {
        let projects = try ListChainsUseCase().run(options: .init(repoPath: options.repoPath))
        guard let project = projects.first(where: { $0.name == options.projectName }) else {
            return nil
        }

        let indexKey = cacheIndexKey(projectName: options.projectName)
        guard let prNumbers = try await gitHubPRService.readCachedIndex(key: indexKey) else {
            return nil
        }

        var enrichedPRsByHash: [String: EnrichedPR] = [:]
        for number in prNumbers {
            guard let pr = try? await gitHubPRService.pullRequest(number: number, useCache: true) else { continue }
            let reviews = (try? await gitHubPRService.reviews(number: number, useCache: true)) ?? []
            let checkRuns = (try? await gitHubPRService.checkRuns(number: number, useCache: true)) ?? []
            let reviewStatus = buildReviewStatus(reviews: reviews)
            let buildStatus = buildBuildStatus(checkRuns: checkRuns, isMergeable: nil)
            let enrichedPR = EnrichedPR(pr: pr, reviewStatus: reviewStatus, buildStatus: buildStatus)
            if let headRefName = pr.headRefName,
               let branchInfo = BranchInfo.fromBranchName(headRefName) {
                enrichedPRsByHash[branchInfo.taskHash] = enrichedPR
            }
        }

        let enrichedTasks = project.tasks.map { task in
            let hash = generateTaskHash(task.description)
            return EnrichedChainTask(task: task, enrichedPR: enrichedPRsByHash[hash])
        }

        return ChainProjectDetail(
            project: project,
            enrichedTasks: enrichedTasks,
            actionItems: buildActionItems(enrichedTasks: enrichedTasks)
        )
    }

    // MARK: - Full network fetch

    public func run(options: Options) async throws -> ChainProjectDetail {
        let projects = try ListChainsUseCase().run(options: .init(repoPath: options.repoPath))
        guard let project = projects.first(where: { $0.name == options.projectName }) else {
            throw GetChainDetailError.projectNotFound(options.projectName)
        }

        let branchPrefix = "\(claudeChainBranchPrefix)\(options.projectName)-"
        let allOpen = try await gitHubPRService.listPullRequests(limit: 500, filter: PRFilter(state: .open))
        let openPRs = allOpen.filter { ($0.headRefName ?? "").hasPrefix(branchPrefix) }
        let allClosed = try await gitHubPRService.listPullRequests(limit: 500, filter: PRFilter(state: .merged))
        let mergedPRs = allClosed.filter { ($0.headRefName ?? "").hasPrefix(branchPrefix) }

        typealias FetchedPRData = (
            pr: PRRadarModelsService.GitHubPullRequest,
            reviews: [GitHubReview],
            checkRuns: [GitHubCheckRun],
            isMergeable: Bool?
        )

        var enrichedPRsByHash: [String: EnrichedPR] = [:]

        // Fetch full data for open PRs
        var prDataByNumber: [Int: FetchedPRData] = [:]
        try await withThrowingTaskGroup(of: FetchedPRData.self) { group in
            for number in openPRs.map({ $0.number }) {
                group.addTask {
                    async let pr = gitHubPRService.pullRequest(number: number, useCache: true)
                    async let reviews = gitHubPRService.reviews(number: number, useCache: false)
                    async let checkRuns = gitHubPRService.checkRuns(number: number, useCache: false)
                    async let isMergeable = gitHubPRService.isMergeable(number: number)
                    return (try await pr, try await reviews, try await checkRuns, try await isMergeable)
                }
            }
            for try await data in group {
                prDataByNumber[data.pr.number] = data
            }
        }

        for (_, data) in prDataByNumber {
            let reviewStatus = buildReviewStatus(reviews: data.reviews)
            let buildStatus = buildBuildStatus(checkRuns: data.checkRuns, isMergeable: data.isMergeable)
            let enrichedPR = EnrichedPR(pr: data.pr, reviewStatus: reviewStatus, buildStatus: buildStatus)
            if let headRefName = data.pr.headRefName,
               let branchInfo = BranchInfo.fromBranchName(headRefName) {
                enrichedPRsByHash[branchInfo.taskHash] = enrichedPR
            }
        }

        // Fetch merged PR metadata for tasks not already matched to an open PR
        let matchedHashes = Set(enrichedPRsByHash.keys)
        let mergedPRsToFetch = mergedPRs.filter { pr in
            guard let headRefName = pr.headRefName,
                  let branchInfo = BranchInfo.fromBranchName(headRefName) else { return false }
            return !matchedHashes.contains(branchInfo.taskHash)
        }
        var mergedPRDataByNumber: [Int: PRRadarModelsService.GitHubPullRequest] = [:]
        try await withThrowingTaskGroup(of: PRRadarModelsService.GitHubPullRequest.self) { group in
            for number in mergedPRsToFetch.map({ $0.number }) {
                group.addTask {
                    try await gitHubPRService.pullRequest(number: number, useCache: true)
                }
            }
            for try await pr in group {
                mergedPRDataByNumber[pr.number] = pr
            }
        }

        for (_, pr) in mergedPRDataByNumber {
            let enrichedPR = EnrichedPR(
                pr: pr,
                reviewStatus: PRReviewStatus(approvedBy: [], pendingReviewers: []),
                buildStatus: .unknown
            )
            if let headRefName = pr.headRefName,
               let branchInfo = BranchInfo.fromBranchName(headRefName) {
                enrichedPRsByHash[branchInfo.taskHash] = enrichedPR
            }
        }

        let enrichedTasks = project.tasks.map { task in
            let hash = generateTaskHash(task.description)
            return EnrichedChainTask(task: task, enrichedPR: enrichedPRsByHash[hash])
        }

        // Save PR number index so the next launch can load from cache instantly
        let allPRNumbers = (openPRs + mergedPRs).map { $0.number }
        try? await gitHubPRService.writeCachedIndex(allPRNumbers, key: cacheIndexKey(projectName: options.projectName))

        return ChainProjectDetail(
            project: project,
            enrichedTasks: enrichedTasks,
            actionItems: buildActionItems(enrichedTasks: enrichedTasks)
        )
    }

    // MARK: - Helpers

    private func cacheIndexKey(projectName: String) -> String {
        "chain-\(projectName)"
    }

    private func buildReviewStatus(reviews: [GitHubReview]) -> PRReviewStatus {
        let approvedBy = reviews
            .filter { $0.state == GitHubReviewState.approved.rawValue }
            .compactMap { $0.author?.login }
        let pendingReviewers = reviews
            .filter { $0.state == GitHubReviewState.pending.rawValue }
            .compactMap { $0.author?.login }
        return PRReviewStatus(approvedBy: approvedBy, pendingReviewers: pendingReviewers)
    }

    private func buildBuildStatus(checkRuns: [GitHubCheckRun], isMergeable: Bool?) -> PRBuildStatus {
        if isMergeable == false {
            return .conflicting
        }
        let failingChecks = checkRuns.filter { $0.isFailing }.map { $0.name }
        if !failingChecks.isEmpty {
            return .failing(checks: failingChecks)
        }
        let pendingChecks = checkRuns.filter { $0.status != "completed" }.map { $0.name }
        if !pendingChecks.isEmpty {
            return .pending(checks: pendingChecks)
        }
        if checkRuns.isEmpty {
            return .unknown
        }
        return .passing
    }

    private func buildActionItems(enrichedTasks: [EnrichedChainTask]) -> [ChainActionItem] {
        var items: [ChainActionItem] = []
        for enrichedTask in enrichedTasks {
            guard let enrichedPR = enrichedTask.enrichedPR, !enrichedPR.isMerged else { continue }
            let prNumber = enrichedPR.pr.number
            if enrichedPR.isDraft {
                items.append(ChainActionItem(
                    kind: .draftNeedsReview,
                    prNumber: prNumber,
                    message: "PR #\(prNumber) is a draft and needs review promotion"
                ))
            }
            switch enrichedPR.buildStatus {
            case .failing(let checks):
                items.append(ChainActionItem(
                    kind: .ciFailure,
                    prNumber: prNumber,
                    message: "PR #\(prNumber) has failing CI: \(checks.joined(separator: ", "))"
                ))
            case .conflicting:
                items.append(ChainActionItem(
                    kind: .mergeConflict,
                    prNumber: prNumber,
                    message: "PR #\(prNumber) has a merge conflict"
                ))
            default:
                break
            }
            if enrichedPR.ageDays > 7 && enrichedPR.reviewStatus.approvedBy.isEmpty {
                items.append(ChainActionItem(
                    kind: .stalePR,
                    prNumber: prNumber,
                    message: "PR #\(prNumber) has been open for \(enrichedPR.ageDays) days with no approvals"
                ))
            }
            if enrichedPR.reviewStatus.pendingReviewers.isEmpty && enrichedPR.reviewStatus.approvedBy.isEmpty {
                items.append(ChainActionItem(
                    kind: .needsReviewers,
                    prNumber: prNumber,
                    message: "PR #\(prNumber) has no reviewers assigned"
                ))
            }
        }
        return items
    }
}

public enum GetChainDetailError: Error {
    case projectNotFound(String)
}
