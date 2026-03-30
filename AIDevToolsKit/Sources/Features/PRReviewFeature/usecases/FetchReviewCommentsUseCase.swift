import Foundation
import GitHubService
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import UseCaseSDK

public struct FetchReviewCommentsUseCase: UseCase {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    /// Loads review comments, optionally fetching fresh data from GitHub first.
    ///
    /// When `cachedOnly` is `false`, fetches comments from GitHub via
    /// `PRAcquisitionService.refreshComments()` and writes them to cache before loading.
    public func execute(
        prNumber: Int,
        minScore: Int = 5,
        commitHash: String? = nil,
        cachedOnly: Bool
    ) async throws -> [ReviewComment] {
        if !cachedOnly {
            let (gitHub, gitOps) = try await GitHubServiceFactory.create(
                repoPath: config.repoPath, githubAccount: config.githubAccount
            )
            let gitHubPRService: (any GitHubPRServiceProtocol)? = config.dataRootURL.map { dataRootURL in
                let normalizedSlug = gitHub.repoSlug.replacingOccurrences(of: "/", with: "-")
                let cacheURL = dataRootURL.appendingPathComponent("github/\(normalizedSlug)")
                return GitHubPRService(rootURL: cacheURL, apiClient: gitHub)
            }
            let historyProvider = LocalGitHistoryProvider(gitOps: gitOps, repoPath: config.repoPath)
            let acquisition = PRAcquisitionService(
                gitHub: gitHub,
                gitOps: gitOps,
                historyProvider: historyProvider,
                gitHubPRService: gitHubPRService
            )
            _ = try await acquisition.refreshComments(
                prNumber: prNumber,
                outputDir: config.resolvedOutputDir,
                authorCache: AuthorCacheService()
            )
        }

        return execute(prNumber: prNumber, minScore: minScore, commitHash: commitHash)
    }

    /// Loads review comments from disk cache.
    public func execute(prNumber: Int, minScore: Int = 5, commitHash: String? = nil) -> [ReviewComment] {
        let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)

        let evalsDir = PRRadarPhasePaths.phaseDirectory(
            outputDir: config.resolvedOutputDir, prNumber: prNumber, phase: .analyze, commitHash: resolvedCommit
        )
        let tasksDir = PRRadarPhasePaths.phaseSubdirectory(
            outputDir: config.resolvedOutputDir, prNumber: prNumber, phase: .prepare,
            subdirectory: PRRadarPhasePaths.prepareTasksSubdir, commitHash: resolvedCommit
        )
        let pending = ViolationService.loadViolations(
            evaluationsDir: evalsDir,
            tasksDir: tasksDir,
            minScore: minScore
        )

        let posted: [GitHubReviewComment] =
            PRDiscoveryService.loadComments(config: config, prNumber: prNumber)?.reviewComments ?? []

        let reconciled = ViolationService.reconcile(pending: pending, posted: posted)
        return CommentSuppressionService.applySuppression(to: reconciled).comments
    }
}
