import AIOutputSDK
import Foundation
import GitHubService
import GitSDK
import Logging
import PipelineSDK
import PRRadarCLIService

private final class TextAccumulator: @unchecked Sendable {
    var text = ""
}

public struct CreatePRStepHandler: StepHandler {
    private let client: any AIClient
    private let git: GitClient
    private let githubService: (any GitHubPRServiceProtocol)?
    private let logger = Logger(label: "CreatePRStepHandler")

    public init(
        client: any AIClient,
        git: GitClient,
        githubService: (any GitHubPRServiceProtocol)? = nil
    ) {
        self.client = client
        self.git = git
        self.githubService = githubService
    }

    public func execute(_ step: PRStepData, context: StepExecutionContext) async throws -> [any PipelineStep] {
        let branch: String
        if let contextBranch = context.gitBranch {
            branch = contextBranch
        } else {
            branch = try await git.getCurrentBranch(workingDirectory: context.workingDirectory)
        }

        try await git.push(
            remote: "origin",
            branch: branch,
            setUpstream: true,
            force: true,
            workingDirectory: context.workingDirectory
        )

        let repoSlug = try await detectRepo(workingDirectory: context.workingDirectory)
        let service = try resolveGitHubService(repoSlug: repoSlug)

        let label = step.label.map { [$0] } ?? []
        let pr = try await service.createPullRequest(
            title: step.titleTemplate,
            body: step.bodyTemplate,
            head: branch,
            base: "",
            draft: true,
            labels: label,
            assignees: [],
            reviewers: []
        )

        try await postPRSummary(
            prNumber: pr.number,
            service: service,
            workingDirectory: context.workingDirectory
        )

        return []
    }

    private func postPRSummary(prNumber: Int, service: any GitHubPRServiceProtocol, workingDirectory: String) async throws {
        let summaryPrompt = """
        You are reviewing a pull request. Analyze the changes made by running \
        `git diff HEAD~1...HEAD` and write a concise markdown summary of what was changed \
        and why. Output ONLY the markdown summary text.
        """
        let options = AIClientOptions(
            dangerouslySkipPermissions: true,
            workingDirectory: workingDirectory
        )
        let summaryText = TextAccumulator()
        let summaryResult = try await client.run(
            prompt: summaryPrompt,
            options: options,
            onOutput: nil,
            onStreamEvent: { event in
                if case .textDelta(let text) = event {
                    summaryText.text += text
                }
            }
        )
        guard summaryResult.exitCode == 0 else {
            throw CreatePRError.commandFailed(
                command: "AI summary generation",
                output: summaryResult.stderr
            )
        }

        let summary = summaryText.text.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.debug("postPRSummary: collected \(summaryText.text.count) chars; preview: \(String(summary.prefix(200)))")
        guard !summary.isEmpty else {
            throw CreatePRError.commandFailed(
                command: "AI summary generation",
                output: "Empty summary generated"
            )
        }

        try await service.postIssueComment(prNumber: prNumber, body: summary)
    }

    private func detectRepo(workingDirectory: String) async throws -> String {
        if let repo = ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"], !repo.isEmpty {
            return repo
        }
        let remoteURL = try await git.remoteGetURL(workingDirectory: workingDirectory)
        guard remoteURL.contains("github.com") else {
            throw CreatePRError.commandFailed(
                command: "repo detection",
                output: "Remote URL does not contain github.com: \(remoteURL)"
            )
        }
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
            throw CreatePRError.commandFailed(
                command: "GitHub auth",
                output: "No GH_TOKEN or GITHUB_TOKEN found in environment"
            )
        }
        let parts = repoSlug.split(separator: "/")
        guard parts.count == 2 else {
            throw CreatePRError.commandFailed(
                command: "repo detection",
                output: "Cannot parse repo slug '\(repoSlug)' as owner/repo"
            )
        }
        return GitHubServiceFactory.make(token: token, owner: String(parts[0]), repo: String(parts[1]))
    }
}
