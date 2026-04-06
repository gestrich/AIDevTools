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
        guard let prNumbers = try await gitHubPRService.readCachedIndex(key: project.cacheIndexKey) else {
            return nil
        }

        var enrichedPRsByHash: [String: EnrichedPR] = [:]
        for number in prNumbers {
            guard let pr = try? await gitHubPRService.pullRequest(number: number, useCache: true) else { continue }
            let reviews = (try? await gitHubPRService.reviews(number: number, useCache: true)) ?? []
            let checkRuns = (try? await gitHubPRService.checkRuns(number: number, useCache: true)) ?? []
            let enrichedPR = EnrichedPR(
                pr: pr,
                reviewStatus: PRReviewStatus(reviews: reviews),
                buildStatus: PRBuildStatus.from(checkRuns: checkRuns, isMergeable: nil)
            )
            if let hash = project.taskHash(for: pr) {
                enrichedPRsByHash[hash] = enrichedPR
            }
        }

        let enrichedTasks = project.tasks.map { task in
            EnrichedChainTask(task: task, enrichedPR: enrichedPRsByHash[generateTaskHash(task.description)])
        }
        return ChainProjectDetail(project: project, enrichedTasks: enrichedTasks)
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
            let enrichedPR = EnrichedPR(
                pr: data.pr,
                reviewStatus: PRReviewStatus(reviews: data.reviews),
                buildStatus: PRBuildStatus.from(checkRuns: data.checkRuns, isMergeable: data.isMergeable)
            )
            if let hash = project.taskHash(for: data.pr) {
                enrichedPRsByHash[hash] = enrichedPR
            }
        }

        // Fetch merged PR metadata for tasks not already matched to an open PR
        let matchedHashes = Set(enrichedPRsByHash.keys)
        let mergedPRsToFetch = mergedPRs.filter { pr in
            guard let headRefName = pr.headRefName else { return false }
            if let branchInfo = BranchInfo.fromBranchName(headRefName) {
                return !matchedHashes.contains(branchInfo.taskHash)
            }
            // Sweep branches use timestamps, not hashes — always fetch and let register() match via PR body
            return true
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
            if let hash = project.taskHash(for: pr) {
                enrichedPRsByHash[hash] = enrichedPR
            }
        }

        let enrichedTasks = project.tasks.map { task in
            EnrichedChainTask(task: task, enrichedPR: enrichedPRsByHash[generateTaskHash(task.description)])
        }

        // Save PR number index so the next launch can load from cache instantly
        let allPRNumbers = (openPRs + mergedPRs).map { $0.number }
        try? await gitHubPRService.writeCachedIndex(allPRNumbers, key: project.cacheIndexKey)

        return ChainProjectDetail(project: project, enrichedTasks: enrichedTasks)
    }
}
