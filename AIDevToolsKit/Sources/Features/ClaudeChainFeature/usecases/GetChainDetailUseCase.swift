import ClaudeChainService
import Foundation
import GitHubService
import PRRadarModelsService
import UseCaseSDK

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

    public func run(options: Options) async throws -> ChainProjectDetail {
        let projects = try ListChainsUseCase().run(options: .init(repoPath: options.repoPath))
        guard let project = projects.first(where: { $0.name == options.projectName }) else {
            throw GetChainDetailError.projectNotFound(options.projectName)
        }

        let repo = try await RepositoryService().getCurrentRepository(workingDirectory: options.repoPath.path)
        let openPRs = PRService(repo: repo).getOpenPrsForProject(project: options.projectName)
        let prNumbers = openPRs.map { $0.number }

        typealias FetchedPRData = (
            pr: PRRadarModelsService.GitHubPullRequest,
            reviews: [GitHubReview],
            checkRuns: [GitHubCheckRun],
            isMergeable: Bool?
        )

        var prDataByNumber: [Int: FetchedPRData] = [:]
        try await withThrowingTaskGroup(of: FetchedPRData.self) { group in
            for number in prNumbers {
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

        var enrichedPRsByHash: [String: EnrichedPR] = [:]
        for (_, data) in prDataByNumber {
            let reviewStatus = buildReviewStatus(reviews: data.reviews)
            let buildStatus = buildBuildStatus(checkRuns: data.checkRuns, isMergeable: data.isMergeable)
            let enrichedPR = EnrichedPR(pr: data.pr, reviewStatus: reviewStatus, buildStatus: buildStatus)
            if let headRefName = data.pr.headRefName,
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
            guard let enrichedPR = enrichedTask.enrichedPR else { continue }
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
