import AIOutputSDK
import CLISDK
import ClaudeChainService
import Foundation
import GitSDK
import Logging
import PipelineSDK
import PipelineService

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
    private let cliClient: CLIClient
    private let dryRun: Bool
    private let gitClient: GitClient
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
        cliClient: CLIClient = CLIClient()
    ) {
        self.baseBranch = baseBranch
        self.client = client
        self.cliClient = cliClient
        self.displayName = displayName
        self.dryRun = dryRun
        self.gitClient = gitClient
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

        let mainCost = context[AITask<String>.metricsKey]?.cost ?? 0.0

        // Generate AI summary
        let (summaryContent, summaryCost) = await generateSummary(workingDirectory: workingDirectory)

        let repoSlug = await ChainPRHelpers.detectRepo(workingDirectory: workingDirectory, git: gitClient)
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
            print("\n=== PR Comment Preview ===")
            print(comment)
            print("=== End PR Comment Preview ===\n")
            logger.debug("ChainPRCommentStep: dry-run, printed comment to console")
            return context
        }

        try await postComment(prNumber: prNumber, repoSlug: repoSlug, comment: comment, workingDirectory: workingDirectory)
        logger.debug("ChainPRCommentStep: posted comment to PR #\(prNumber)")
        return context
    }

    // MARK: - Private

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

    private func postComment(prNumber: String, repoSlug: String, comment: String, workingDirectory: String) async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pr_comment_\(UUID().uuidString).md")
        try comment.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var args = ["pr", "comment", prNumber, "--body-file", tempURL.path]
        if !repoSlug.isEmpty { args += ["--repo", repoSlug] }
        let result = try await cliClient.execute(
            command: "gh",
            arguments: args,
            workingDirectory: workingDirectory,
            environment: nil,
            printCommand: false
        )
        guard result.isSuccess else {
            throw PRStepError.commandFailed(command: "gh pr comment", output: result.errorOutput)
        }
    }
}

