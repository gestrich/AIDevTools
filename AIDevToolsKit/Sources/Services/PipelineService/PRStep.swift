import Foundation
import GitHubService
import GitSDK
import Logging
import OctokitSDK
import PipelineSDK
import PRRadarCLIService
import PRRadarModelsService

public struct PRStep: PipelineNode {
    public static var prNumberKey: PipelineContextKey<String> { .init("PRStep.prNumber") }
    public static var prURLKey: PipelineContextKey<String> { .init("PRStep.prURL") }

    public let baseBranch: String
    public let configuration: PRConfiguration
    public let displayName: String
    private let gitClient: GitClient
    private let githubService: (any GitHubPRServiceProtocol)?
    public let id: String
    public let prTemplatePath: String?
    public let projectName: String?
    public let taskDescription: String?

    private let logger = Logger(label: "PRStep")

    public init(
        id: String,
        displayName: String,
        baseBranch: String,
        configuration: PRConfiguration,
        gitClient: GitClient,
        projectName: String? = nil,
        taskDescription: String? = nil,
        prTemplatePath: String? = nil,
        githubService: (any GitHubPRServiceProtocol)? = nil
    ) {
        self.baseBranch = baseBranch
        self.configuration = configuration
        self.displayName = displayName
        self.gitClient = gitClient
        self.githubService = githubService
        self.id = id
        self.prTemplatePath = prTemplatePath
        self.projectName = projectName
        self.taskDescription = taskDescription
    }

    public func run(
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineNodeProgress) -> Void
    ) async throws -> PipelineContext {
        let workingDirectory = context[PipelineContext.workingDirectoryKey] ?? ""
        logger.debug("PRStep.run: workingDirectory='\(workingDirectory)'")

        let branch = try await gitClient.getCurrentBranch(workingDirectory: workingDirectory)
        logger.debug("PRStep.run: branch='\(branch)', baseBranch='\(baseBranch)'")

        // Commit any uncommitted changes (Claude may leave changes unstaged/uncommitted)
        if let taskDescription {
            let uncommitted = try await gitClient.status(workingDirectory: workingDirectory)
            if !uncommitted.isEmpty {
                logger.debug("PRStep.run: found uncommitted changes, staging and committing")
                try await gitClient.addAll(workingDirectory: workingDirectory)
                let staged = try await gitClient.diffCachedNames(workingDirectory: workingDirectory)
                if !staged.isEmpty {
                    try await gitClient.commit(message: "Complete task: \(taskDescription)", workingDirectory: workingDirectory)
                    logger.debug("PRStep.run: committed \(staged.count) file(s)")
                } else {
                    logger.debug("PRStep.run: no staged changes after add (already committed by Claude)")
                }
            } else {
                logger.debug("PRStep.run: no uncommitted changes")
            }
        }

        try await gitClient.push(
            remote: "origin",
            branch: branch,
            setUpstream: true,
            force: true,
            workingDirectory: workingDirectory
        )

        let repoSlug = try await detectRepoSlug(workingDirectory: workingDirectory)
        let service = try resolveGitHubService(repoSlug: repoSlug)

        if let maxOpen = configuration.maxOpenPRs, !repoSlug.isEmpty {
            let openCount = try await service.listPullRequests(limit: 500, filter: PRFilter(state: .open)).count
            guard openCount < maxOpen else {
                throw PipelineError.capacityExceeded(openCount: openCount, maxOpen: maxOpen)
            }
        }

        let title: String
        let body: String
        if let taskDescription {
            let prefix = projectName.map { "ClaudeChain: [\($0)] " } ?? "ClaudeChain: "
            let maxTask = 80 - prefix.count
            let truncated = taskDescription.count > maxTask
                ? String(taskDescription.prefix(maxTask - 3)) + "..."
                : taskDescription
            title = "\(prefix)\(truncated)"
            if let path = prTemplatePath, let template = try? String(contentsOfFile: path, encoding: .utf8) {
                body = template.replacingOccurrences(of: "{{TASK_DESCRIPTION}}", with: taskDescription)
            } else {
                body = taskDescription
            }
        } else {
            title = branch
            body = ""
        }

        logger.debug("PRStep.run: creating PR with title: '\(title)'")
        let pr: CreatedPullRequest
        do {
            pr = try await service.createPullRequest(
                title: title,
                body: body,
                head: branch,
                base: baseBranch,
                draft: true,
                labels: configuration.labels,
                assignees: configuration.assignees,
                reviewers: configuration.reviewers
            )
            logger.debug("PRStep.run: PR created at \(pr.htmlURL)")
        } catch {
            logger.warning("PRStep.run: createPullRequest threw, attempting recovery via pullRequestByHeadBranch: \(error)")
            guard let existingPR = try? await service.pullRequestByHeadBranch(branch: branch) else {
                throw error
            }
            pr = existingPR
        }

        var updated = context
        updated[Self.prURLKey] = pr.htmlURL
        updated[Self.prNumberKey] = String(pr.number)
        return updated
    }

    // MARK: - Private

    private func detectRepoSlug(workingDirectory: String) async throws -> String {
        if let repo = ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"], !repo.isEmpty {
            return repo
        }
        let remoteURL = try await gitClient.remoteGetURL(workingDirectory: workingDirectory)
        return remoteURL
            .replacingOccurrences(of: "git@github.com:", with: "")
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveGitHubService(repoSlug: String) throws -> any GitHubPRServiceProtocol {
        if let service = githubService {
            return service
        }
        let env = ProcessInfo.processInfo.environment
        guard let token = env["GH_TOKEN"] ?? env["GITHUB_TOKEN"] else {
            throw PRStepError.commandFailed(
                command: "GitHub auth",
                output: "No GH_TOKEN or GITHUB_TOKEN found in environment"
            )
        }
        let parts = repoSlug.split(separator: "/")
        guard parts.count == 2 else {
            throw PRStepError.commandFailed(
                command: "repo detection",
                output: "Cannot parse repo slug '\(repoSlug)' as owner/repo"
            )
        }
        return GitHubServiceFactory.make(token: token, owner: String(parts[0]), repo: String(parts[1]))
    }
}
