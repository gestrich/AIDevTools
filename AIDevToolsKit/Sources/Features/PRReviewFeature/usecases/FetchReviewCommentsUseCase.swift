import CredentialService
import Foundation
import GitHubService
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import UseCaseSDK

public struct FetchReviewCommentsUseCase: UseCase {

    private let config: PRRadarRepoConfig

    public init(config: PRRadarRepoConfig) {
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
            guard let githubAccount = config.githubAccount else {
                throw CredentialError.notConfigured(account: config.name)
            }
            let cacheURL = try config.requireGitHubCacheURL()
            let gitHub = try await GitHubServiceFactory.createGitHubAPI(repoPath: config.repoPath, githubAccount: githubAccount, explicitToken: config.explicitToken)
            let gitOps = try await GitHubServiceFactory.createGitOps(githubAccount: githubAccount, explicitToken: config.explicitToken)
            let gitHubPRService = GitHubPRService(rootURL: cacheURL, apiClient: gitHub)
            let historyProvider = LocalGitHistoryProvider(gitOps: gitOps, repoPath: config.repoPath)
            let acquisition = PRAcquisitionService(
                gitHub: gitHub,
                gitOps: gitOps,
                historyProvider: historyProvider,
                gitHubPRService: gitHubPRService
            )
            _ = try await acquisition.refreshComments(
                prNumber: prNumber,
                authorCache: AuthorCacheService()
            )
        }

        return await execute(prNumber: prNumber, minScore: minScore, commitHash: commitHash)
    }

    /// Loads review comments from disk cache.
    public func execute(prNumber: Int, minScore: Int = 5, commitHash: String? = nil) async -> [ReviewComment] {
        let resolvedCommit: String?
        if let hash = commitHash {
            resolvedCommit = hash
        } else {
            resolvedCommit = await FetchPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)
        }

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
            (await PRDiscoveryService.loadComments(config: config, prNumber: prNumber))?.reviewComments ?? []

        let reconciled = ViolationService.reconcile(pending: pending, posted: posted)
        return CommentSuppressionService.applySuppression(to: reconciled).comments
    }

}
