import Foundation
import GitHubService
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import UseCaseSDK

public struct SyncPRUseCase: StreamingUseCase {

    private let config: PRRadarRepoConfig

    public init(config: PRRadarRepoConfig) {
        self.config = config
    }

    public static func parseOutput(config: PRRadarRepoConfig, prNumber: Int, commitHash: String? = nil) async -> SyncSnapshot {
        let resolvedCommit: String?
        if let hash = commitHash {
            resolvedCommit = hash
        } else {
            resolvedCommit = await resolveCommitHash(config: config, prNumber: prNumber)
        }

        let files = OutputFileReader.files(
            in: config,
            prNumber: prNumber,
            phase: .diff,
            commitHash: resolvedCommit
        )

        let prDiff = await LoadPRDiffUseCase(config: config).execute(prNumber: prNumber, commitHash: resolvedCommit)

        let comments = await PRDiscoveryService.loadComments(config: config, prNumber: prNumber)

        return SyncSnapshot(
            prDiff: prDiff,
            files: files,
            commentCount: comments?.comments.count ?? 0,
            reviewCount: comments?.reviews.count ?? 0,
            reviewCommentCount: comments?.reviewComments.count ?? 0,
            commitHash: resolvedCommit
        )
    }

    /// Resolve the commit hash from cached PR metadata, or scan analysis/ for the latest commit directory.
    public static func resolveCommitHash(config: PRRadarRepoConfig, prNumber: Int) async -> String? {
        if let pr = await PRDiscoveryService.loadGitHubPR(config: config, prNumber: prNumber),
           let fullHash = pr.headRefOid {
            return String(fullHash.prefix(7))
        }
        let analysisRoot = "\(config.resolvedOutputDir)/\(prNumber)/\(PRRadarPhasePaths.analysisDirectoryName)"
        if let dirs = try? FileManager.default.contentsOfDirectory(atPath: analysisRoot) {
            return dirs.sorted().last
        }
        return nil
    }

    public func execute(prNumber: Int, force: Bool = false) -> AsyncThrowingStream<PhaseProgress<SyncSnapshot>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .diff))

            Task {
                do {
                    try Task.checkCancellation()

                    let (gitHub, gitOps) = try await GitHubServiceFactory.create(repoPath: config.repoPath, githubAccount: config.githubAccount)

                    try Task.checkCancellation()

                    let cacheURL = try config.requireGitHubCacheURL()
                    let gitHubPRService = GitHubPRService(rootURL: cacheURL, apiClient: gitHub)

                    if !force {
                        let cachedPR = try? await gitHubPRService.pullRequest(number: prNumber, useCache: true)
                        if let cachedUpdatedAt = cachedPR?.updatedAt {
                            let currentUpdatedAt = try await gitHub.getPRUpdatedAt(number: prNumber)
                            if cachedUpdatedAt == currentUpdatedAt {
                                let snapshot = await Self.parseOutput(config: config, prNumber: prNumber)
                                if snapshot.prDiff != nil {
                                    continuation.yield(.completed(output: snapshot))
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                    }

                    let prMetadata = try await gitHub.getPullRequest(number: prNumber)
                    guard let baseBranch = prMetadata.baseRefName,
                          let headBranch = prMetadata.headRefName else {
                        throw PRAcquisitionService.AcquisitionError.missingHeadCommitSHA
                    }
                    let historyProvider = GitHubServiceFactory.createHistoryProvider(
                        diffSource: config.diffSource,
                        gitHub: gitHub,
                        gitOps: gitOps,
                        repoPath: config.repoPath,
                        prNumber: prNumber,
                        baseBranch: baseBranch,
                        headBranch: headBranch
                    )
                    let acquisition = PRAcquisitionService(
                        gitHub: gitHub,
                        gitOps: gitOps,
                        historyProvider: historyProvider,
                        gitHubPRService: gitHubPRService
                    )
                    let authorCache = AuthorCacheService()

                    continuation.yield(.log(text: "Fetching PR #\(prNumber) from GitHub...\n"))

                    let result = try await acquisition.acquire(
                        prNumber: prNumber,
                        outputDir: config.resolvedOutputDir,
                        authorCache: authorCache
                    )

                    try Task.checkCancellation()

                    let comments = result.comments
                    continuation.yield(.log(text: "Diff acquired: \(result.diff.hunks.count) hunks across \(result.diff.uniqueFiles.count) files\n"))
                    continuation.yield(.log(text: "Comments: \(comments.comments.count) issue, \(comments.reviews.count) reviews, \(comments.reviewComments.count) inline\n"))

                    for rc in comments.reviewComments {
                        let author = rc.author?.login ?? "unknown"
                        let file = rc.path.split(separator: "/").last.map(String.init) ?? rc.path
                        continuation.yield(.log(text: "  [\(author)] \(file):\(rc.line ?? 0) — \(rc.body.prefix(80))\n"))
                    }

                    let snapshot = await Self.parseOutput(config: config, prNumber: prNumber, commitHash: result.commitHash)
                    continuation.yield(.completed(output: snapshot))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }

}
