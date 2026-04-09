import Foundation
import GitHubService
import OctokitSDK
import GitSDK
import PRRadarConfigService
import PRRadarModelsService

public struct PRAcquisitionService: Sendable {

    private let gitHub: GitHubAPIService
    private let gitOps: GitService
    private let historyProvider: GitHistoryProvider
    private let gitHubPRService: any GitHubPRServiceProtocol
    private let imageDownload: ImageDownloadService

    public init(
        gitHub: GitHubAPIService,
        gitOps: GitService,
        historyProvider: GitHistoryProvider,
        gitHubPRService: any GitHubPRServiceProtocol,
        imageDownload: ImageDownloadService = ImageDownloadService()
    ) {
        self.gitHub = gitHub
        self.gitOps = gitOps
        self.historyProvider = historyProvider
        self.gitHubPRService = gitHubPRService
        self.imageDownload = imageDownload
    }

    /// Fetch comments from GitHub, resolve author names, and write to the shared GitHub cache.
    public func refreshComments(
        prNumber: Int,
        authorCache: AuthorCacheService
    ) async throws -> GitHubPullRequestComments {
        var comments: GitHubPullRequestComments
        do {
            comments = try await gitHubPRService.comments(number: prNumber, useCache: false)
        } catch {
            throw AcquisitionError.fetchCommentsFailed(underlying: error)
        }

        let logins = collectCommentAuthorLogins(comments: comments)
        if !logins.isEmpty {
            let nameMap = try await gitHub.resolveAuthorNames(logins: logins, cache: authorCache)
            comments = comments.withAuthorNames(from: nameMap)
        }

        if !comments.reviewComments.isEmpty {
            let resolvedIDs = try await gitHub.fetchResolvedReviewCommentIDs(number: prNumber)
            comments = comments.withReviewThreadResolution(resolvedCommentIDs: resolvedIDs)
        }

        try await gitHubPRService.writeComments(comments, number: prNumber)

        return comments
    }

    /// Fetch all PR data artifacts and write them to disk.
    public func acquire(
        prNumber: Int,
        outputDir: String,
        authorCache: AuthorCacheService
    ) async throws -> AcquisitionResult {
        let repository: GitHubRepository
        var pullRequest: GitHubPullRequest

        do {
            try await gitHubPRService.updateRepository()
            repository = try await gitHubPRService.repository(useCache: true)
        } catch {
            throw AcquisitionError.fetchRepositoryFailed(underlying: error)
        }
        do {
            try await gitHubPRService.updatePR(number: prNumber)
            pullRequest = try await gitHubPRService.pullRequest(number: prNumber, useCache: true)
        } catch {
            throw AcquisitionError.fetchMetadataFailed(underlying: error)
        }

        let rawDiff: String
        do {
            rawDiff = try await historyProvider.getRawDiff()
        } catch {
            throw AcquisitionError.fetchDiffFailed(underlying: error)
        }

        let comments = try await refreshComments(
            prNumber: prNumber,
            authorCache: authorCache
        )

        if let prLogin = pullRequest.author?.login {
            let nameMap = try await gitHub.resolveAuthorNames(logins: [prLogin], cache: authorCache)
            pullRequest = pullRequest.withAuthorNames(from: nameMap)
            try await gitHubPRService.writePR(pullRequest, number: prNumber)
        }

        guard let fullCommitHash = pullRequest.headRefOid,
              let baseRefName = pullRequest.baseRefName else {
            throw AcquisitionError.missingHeadCommitSHA
        }
        let shortCommitHash = String(fullCommitHash.prefix(7))

        let metadataDir = PRRadarPhasePaths.phaseDirectory(
            outputDir: outputDir,
            prNumber: prNumber,
            phase: .metadata
        )
        try PRRadarPhasePaths.ensureDirectoryExists(at: metadataDir)

        let imageURLMap = try await downloadImages(
            prNumber: prNumber,
            pullRequest: pullRequest,
            comments: comments,
            phaseDir: metadataDir
        )
        if !imageURLMap.isEmpty {
            let mapJSON = try JSONEncoder.prettyPrinted.encode(imageURLMap)
            try write(mapJSON, to: "\(metadataDir)/\(PRRadarPhasePaths.imageURLMapFilename)")
        }

        try PhaseResultWriter.writeSuccess(
            phase: .metadata,
            outputDir: outputDir,
            prNumber: prNumber,
            stats: PhaseStats(
                artifactsProduced: 3,
                metadata: ["commitHash": shortCommitHash]
            )
        )

        let diffDir = PRRadarPhasePaths.phaseDirectory(
            outputDir: outputDir,
            prNumber: prNumber,
            phase: .diff,
            commitHash: shortCommitHash
        )
        try PRRadarPhasePaths.ensureDirectoryExists(at: diffDir)

        try write(rawDiff, to: "\(diffDir)/\(PRRadarPhasePaths.diffRawFilename)")

        let gitDiff = GitDiff.fromDiffContent(rawDiff, commitHash: fullCommitHash)
        let parsedDiffJSON = try JSONEncoder.prettyPrinted.encode(gitDiff)
        try write(parsedDiffJSON, to: "\(diffDir)/\(PRRadarPhasePaths.diffParsedJSONFilename)")

        let parsedMD = formatDiffAsMarkdown(gitDiff)
        try write(parsedMD, to: "\(diffDir)/\(PRRadarPhasePaths.diffParsedMarkdownFilename)")

        let (effectiveDiffJSON, effectiveMD, movesJSON, prDiffJSON) = try await runEffectiveDiff(
            gitDiff: gitDiff,
            baseRefName: baseRefName,
            headCommit: fullCommitHash
        )
        try write(effectiveDiffJSON, to: "\(diffDir)/\(PRRadarPhasePaths.effectiveDiffParsedJSONFilename)")
        try write(effectiveMD, to: "\(diffDir)/\(PRRadarPhasePaths.effectiveDiffParsedMarkdownFilename)")
        try write(movesJSON, to: "\(diffDir)/\(PRRadarPhasePaths.effectiveDiffMovesFilename)")
        try write(prDiffJSON, to: "\(diffDir)/\(PRRadarPhasePaths.prDiffFilename)")

        try PhaseResultWriter.writeSuccess(
            phase: .diff,
            outputDir: outputDir,
            prNumber: prNumber,
            commitHash: shortCommitHash,
            stats: PhaseStats(
                artifactsProduced: 7,
                metadata: ["files": String(gitDiff.uniqueFiles.count), "hunks": String(gitDiff.hunks.count)]
            )
        )

        return AcquisitionResult(
            pullRequest: pullRequest,
            diff: gitDiff,
            comments: comments,
            repository: repository,
            commitHash: shortCommitHash
        )
    }

    // MARK: - Private

    private func collectCommentAuthorLogins(
        comments: GitHubPullRequestComments
    ) -> Set<String> {
        var logins = Set<String>()
        for c in comments.comments {
            if let login = c.author?.login {
                logins.insert(login)
            }
        }
        for r in comments.reviews {
            if let login = r.author?.login {
                logins.insert(login)
            }
        }
        for rc in comments.reviewComments {
            if let login = rc.author?.login {
                logins.insert(login)
            }
        }
        return logins
    }

    private func downloadImages(
        prNumber: Int,
        pullRequest: GitHubPullRequest,
        comments: GitHubPullRequestComments,
        phaseDir: String
    ) async throws -> [String: String] {
        let bodyHTML = try await gitHub.fetchBodyHTML(number: prNumber)
        let imagesDir = "\(phaseDir)/images"

        var allResolved: [String: URL] = [:]

        if let body = pullRequest.body {
            let resolved = imageDownload.resolveImageURLs(body: body, bodyHTML: bodyHTML)
            allResolved.merge(resolved) { _, new in new }
        }

        for comment in comments.comments {
            let resolved = imageDownload.resolveImageURLs(body: comment.body, bodyHTML: bodyHTML)
            allResolved.merge(resolved) { _, new in new }
        }

        guard !allResolved.isEmpty else { return [:] }

        return try await imageDownload.downloadImages(urls: allResolved, to: imagesDir)
    }

    private func write(_ string: String, to path: String) throws {
        try string.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func write(_ data: Data, to path: String) throws {
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func runEffectiveDiff(
        gitDiff: GitDiff,
        baseRefName: String,
        headCommit: String
    ) async throws -> (diffJSON: Data, diffMD: String, movesJSON: Data, prDiffJSON: Data) {
        let mergeBase = try await historyProvider.getMergeBase(
            commit1: "origin/\(baseRefName)",
            commit2: headCommit
        )

        var oldFiles: [String: String] = [:]
        var newFiles: [String: String] = [:]
        let deleted = gitDiff.deletedFiles
        let added = gitDiff.newFiles
        for filePath in gitDiff.uniqueFiles {
            if !added.contains(filePath) {
                oldFiles[filePath] = try? await historyProvider.getFileContent(commit: mergeBase, filePath: filePath)
            }
            if !deleted.contains(filePath) {
                newFiles[filePath] = try? await historyProvider.getFileContent(commit: headCommit, filePath: filePath)
            }
        }

        let result = try await runEffectiveDiffPipeline(
            gitDiff: gitDiff,
            oldFiles: oldFiles,
            newFiles: newFiles,
            rediff: gitOps.diffNoIndex
        )

        let effectiveDiffJSON = try JSONEncoder.prettyPrinted.encode(result.effectiveDiff)
        let effectiveMD = formatDiffAsMarkdown(result.effectiveDiff)
        let movesJSON = try JSONEncoder.prettyPrinted.encode(result.moveReport)
        let prDiffJSON = try JSONEncoder.prettyPrinted.encode(result.prDiff)

        return (effectiveDiffJSON, effectiveMD, movesJSON, prDiffJSON)
    }

    private func formatDiffAsMarkdown(_ diff: GitDiff) -> String {
        var lines: [String] = []
        lines.append("# Diff (commit: \(diff.commitHash))")
        lines.append("")

        for hunk in diff.hunks {
            lines.append("## \(hunk.filePath)")
            lines.append("```diff")
            lines.append(hunk.content)
            lines.append("```")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    public enum AcquisitionError: LocalizedError {
        case fetchRepositoryFailed(underlying: Error)
        case fetchDiffFailed(underlying: Error)
        case fetchMetadataFailed(underlying: Error)
        case fetchCommentsFailed(underlying: Error)
        case missingHeadCommitSHA

        public var errorDescription: String? {
            switch self {
            case .fetchRepositoryFailed(let error):
                "Failed to fetch repository info: \(error.localizedDescription)"
            case .fetchDiffFailed(let error):
                "Failed to fetch PR diff: \(error.localizedDescription)"
            case .fetchMetadataFailed(let error):
                "Failed to fetch PR metadata: \(error.localizedDescription)"
            case .fetchCommentsFailed(let error):
                "Failed to fetch PR comments: \(error.localizedDescription)"
            case .missingHeadCommitSHA:
                "PR is missing headRefOid (head commit SHA)"
            }
        }
    }

    public struct AcquisitionResult: Sendable {
        public let pullRequest: GitHubPullRequest
        public let diff: GitDiff
        public let comments: GitHubPullRequestComments
        public let repository: GitHubRepository
        public let commitHash: String
    }
}

