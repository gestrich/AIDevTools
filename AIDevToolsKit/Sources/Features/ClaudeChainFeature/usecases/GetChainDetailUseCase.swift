import ClaudeChainService
import Foundation
import GitHubService
import PRRadarModelsService
import UseCaseSDK

public struct GetChainDetailUseCase: UseCase, StreamingUseCase {

    public struct Options: Sendable {
        public let project: ChainProject

        public init(project: ChainProject) {
            self.project = project
        }
    }

    private let gitHubPRService: any GitHubPRServiceProtocol

    public init(gitHubPRService: any GitHubPRServiceProtocol) {
        self.gitHubPRService = gitHubPRService
    }

    // MARK: - Cache-first then network stream

    /// Yields cached data immediately (if available), then yields fresh data from the network.
    public func stream(options: Options) -> AsyncThrowingStream<ChainProjectDetail, Error> {
        AsyncThrowingStream { continuation in
            Task {
                if let cached = try? await loadCached(options: options) {
                    continuation.yield(cached)
                }
                do {
                    let detail = try await run(options: options)
                    continuation.yield(detail)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Cache-first load (no network)

    private func loadCached(options: Options) async throws -> ChainProjectDetail? {
        let project = options.project
        let indexKey = cacheIndexKey(projectName: project.name)
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
            register(enrichedPR, into: &enrichedPRsByHash)
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
        let project = options.project
        let branchPrefix = project.branchPrefix
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
            register(enrichedPR, into: &enrichedPRsByHash)
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
            register(enrichedPR, into: &enrichedPRsByHash)
        }

        let enrichedTasks = project.tasks.map { task in
            let hash = generateTaskHash(task.description)
            return EnrichedChainTask(task: task, enrichedPR: enrichedPRsByHash[hash])
        }

        // Save PR number index so the next launch can load from cache instantly
        let allPRNumbers = (openPRs + mergedPRs).map { $0.number }
        try? await gitHubPRService.writeCachedIndex(allPRNumbers, key: cacheIndexKey(projectName: project.name))

        return ChainProjectDetail(
            project: project,
            enrichedTasks: enrichedTasks,
            actionItems: buildActionItems(enrichedTasks: enrichedTasks)
        )
    }

    // MARK: - Helpers

    private func register(_ enrichedPR: EnrichedPR, into dict: inout [String: EnrichedPR]) {
        guard let headRefName = enrichedPR.pr.headRefName,
              let branchInfo = BranchInfo.fromBranchName(headRefName) else { return }
        dict[branchInfo.taskHash] = enrichedPR
    }

    private func cacheIndexKey(projectName: String) -> String {
        "chain-\(projectName)"
    }

    private func buildReviewStatus(reviews: [GitHubReview]) -> PRReviewStatus {
        let approvedBy = Array(Set(
            reviews
                .filter { $0.state == .approved }
                .compactMap { $0.author?.login }
        ))
        let pendingReviewers = Array(Set(
            reviews
                .filter { $0.state == .pending }
                .compactMap { $0.author?.login }
        ))
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
        let pendingChecks = checkRuns.filter { $0.status != .completed }.map { $0.name }
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

        }
        return items
    }
}
