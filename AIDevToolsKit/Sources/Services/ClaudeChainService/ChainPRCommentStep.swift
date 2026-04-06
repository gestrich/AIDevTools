import AIOutputSDK
import Foundation
import GitHubService
import GitSDK
import Logging
import PipelineSDK
import PipelineService
import PRRadarCLIService

/// Pipeline step that generates an AI summary and posts the full PR comment.
///
/// Runs after `PRStep`. Reads `PRStep.prURLKey` and `PRStep.prNumberKey` from
/// context, generates an AI-authored summary of the diff, then posts a comment
/// containing the summary and cost breakdown using `PullRequestCreatedReport`.
public struct ChainPRCommentStep: PipelineNode {

    public let id: String
    public let displayName: String

    private let baseBranch: String
    private let client: any AIClient
    private let dryRun: Bool
    private let gitClient: GitClient
    private let githubService: (any GitHubPRServiceProtocol)?
    private let logger = Logger(label: "ChainPRCommentStep")
    private let projectName: String
    private let taskDescription: String

    public init(
        id: String,
        displayName: String,
        baseBranch: String,
        client: any AIClient,
        gitClient: GitClient,
        projectName: String,
        taskDescription: String,
        dryRun: Bool = false,
        githubService: (any GitHubPRServiceProtocol)? = nil
    ) {
        self.baseBranch = baseBranch
        self.client = client
        self.displayName = displayName
        self.dryRun = dryRun
        self.gitClient = gitClient
        self.githubService = githubService
        self.id = id
        self.projectName = projectName
        self.taskDescription = taskDescription
    }

    public func run(
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineNodeProgress) -> Void
    ) async throws -> PipelineContext {
        let workingDirectory = context[PipelineContext.workingDirectoryKey] ?? ""
        let prNumber: String
        let prURL: String
        if dryRun {
            prNumber = context[PRStep.prNumberKey] ?? "N/A"
            prURL = context[PRStep.prURLKey] ?? "N/A"
        } else {
            guard let num = context[PRStep.prNumberKey],
                  let url = context[PRStep.prURLKey] else {
                logger.debug("ChainPRCommentStep: no PR number/URL in context, skipping comment")
                return context
            }
            prNumber = num
            prURL = url
        }

        logger.debug("ChainPRCommentStep: generating summary for PR #\(prNumber)")

        let mainCost = context[PipelineContextKey<AIMetrics>("AITask.metrics")]?.cost ?? 0.0

        let (summaryContent, summaryCost) = await generateSummary(workingDirectory: workingDirectory)

        let repoSlug = await detectRepo(workingDirectory: workingDirectory)
        let costBreakdown = CostBreakdown(mainCost: mainCost, summaryCost: summaryCost)
        let report = PullRequestCreatedReport(
            prNumber: prNumber,
            prURL: prURL,
            projectName: projectName,
            task: taskDescription,
            costBreakdown: costBreakdown,
            repo: repoSlug,
            runID: "",
            summaryContent: summaryContent
        )

        let formatter = MarkdownReportFormatter()
        let comment = formatter.format(report.buildCommentElements())

        if dryRun {
            logger.info("ChainPRCommentStep: dry-run PR comment preview:\n\(comment)")
            return context
        }

        try await postComment(prNumber: prNumber, repoSlug: repoSlug, comment: comment)
        logger.debug("ChainPRCommentStep: posted comment to PR #\(prNumber)")
        return context
    }

    // MARK: - Private

    private func detectRepo(workingDirectory: String) async -> String {
        if let repo = ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"], !repo.isEmpty {
            return repo
        }
        guard let remoteURL = try? await gitClient.remoteGetURL(workingDirectory: workingDirectory),
              remoteURL.contains("github.com") else {
            return ""
        }
        return remoteURL
            .replacingOccurrences(of: "git@github.com:", with: "")
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: ".git", with: "")
    }

    private func generateSummary(workingDirectory: String) async -> (String?, Double) {
        let prompt = """
        Analyze the changes made by running `git diff \(baseBranch)...HEAD` and write a \
        concise markdown summary of what was changed and why. Output ONLY the markdown text.
        """
        let options = AIClientOptions(dangerouslySkipPermissions: true, workingDirectory: workingDirectory)
        let accumulator = StreamAccumulator()
        do {
            _ = try await client.run(
                prompt: prompt,
                options: options,
                onOutput: nil,
                onStreamEvent: { event in _ = accumulator.apply(event) }
            )
        } catch {
            logger.warning("ChainPRCommentStep: summary generation failed: \(error)")
            return (nil, 0.0)
        }
        let text = accumulator.blocks.compactMap {
            if case .text(let t) = $0 { return t } else { return nil }
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let cost = accumulator.blocks.compactMap {
            if case .metrics(_, let cost, _) = $0 { return cost } else { return nil }
        }.last ?? 0.0
        return (text.isEmpty ? nil : text, cost)
    }

    private func postComment(prNumber: String, repoSlug: String, comment: String) async throws {
        let service: any GitHubPRServiceProtocol
        if let injected = githubService {
            service = injected
        } else {
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
            service = GitHubServiceFactory.make(
                token: token,
                owner: String(parts[0]),
                repo: String(parts[1])
            )
        }
        guard let number = Int(prNumber) else {
            throw PRStepError.commandFailed(
                command: "PR comment",
                output: "Invalid PR number: \(prNumber)"
            )
        }
        try await service.postIssueComment(prNumber: number, body: comment)
    }
}
