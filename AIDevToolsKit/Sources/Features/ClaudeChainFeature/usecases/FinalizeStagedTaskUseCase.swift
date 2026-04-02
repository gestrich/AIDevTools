import AIOutputSDK
import ClaudeChainSDK
import ClaudeChainService
import CredentialService
import Foundation
import GitSDK
import Logging
import PipelineSDK
import UseCaseSDK

private final class TextAccumulator: @unchecked Sendable {
    var text = ""
}

public struct FinalizeStagedTaskUseCase: UseCase {

    public struct Options: Sendable {
        public let baseBranch: String
        public let branchName: String
        public let dryRun: Bool
        public let githubAccount: String?
        public let projectName: String
        public let repoPath: URL
        public let taskDescription: String

        public init(repoPath: URL, projectName: String, baseBranch: String, branchName: String, taskDescription: String, githubAccount: String? = nil, dryRun: Bool = false) {
            self.baseBranch = baseBranch
            self.branchName = branchName
            self.dryRun = dryRun
            self.githubAccount = githubAccount
            self.projectName = projectName
            self.repoPath = repoPath
            self.taskDescription = taskDescription
        }
    }

    public struct Result: Sendable {
        public let message: String
        public let prNumber: String?
        public let prURL: String?
        public let success: Bool
        public let taskDescription: String?

        public init(
            success: Bool,
            message: String,
            prURL: String? = nil,
            prNumber: String? = nil,
            taskDescription: String? = nil
        ) {
            self.message = message
            self.prNumber = prNumber
            self.prURL = prURL
            self.success = success
            self.taskDescription = taskDescription
        }
    }

    public typealias Progress = RunChainTaskUseCase.Progress

    private let client: any AIClient
    private let git: GitClient
    private let logger = Logger(label: "FinalizeStagedTaskUseCase")

    public init(client: any AIClient, git: GitClient = GitClient()) {
        self.client = client
        self.git = git
    }

    public func run(
        options: Options,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> Result {
        if let githubAccount = options.githubAccount {
            let resolver = CredentialResolver(
                settingsService: SecureSettingsService(),
                githubAccount: githubAccount
            )
            if case .token(let token) = resolver.getGitHubAuth() {
                setenv("GH_TOKEN", token, 1)
            }
        }

        let repoDir = options.repoPath.path
        let chainDir = options.repoPath.appendingPathComponent("claude-chain").path
        let project = Project(
            name: options.projectName,
            basePath: (chainDir as NSString).appendingPathComponent(options.projectName)
        )
        let githubClient = GitHubClient(workingDirectory: chainDir)
        let repository = ProjectRepository(repo: "", gitHubOperations: GitHubOperations(githubClient: githubClient))
        let projectConfig = try? repository.loadLocalConfiguration(project: project)

        logger.debug("finalize: checking out \(options.branchName)")
        try await git.checkout(ref: options.branchName, workingDirectory: repoDir)

        onProgress?(.finalizing)

        // Mark task complete in spec.md
        let specURL = URL(fileURLWithPath: project.specPath)
        let pipelineSource = MarkdownPipelineSource(fileURL: specURL, format: .task, appendCreatePRStep: false)
        let pipeline = try await pipelineSource.load()
        let codeSteps = pipeline.steps.compactMap { $0 as? CodeChangeStep }

        guard let step = codeSteps.first(where: { $0.description == options.taskDescription }) else {
            let error = "Task not found in spec.md: \(options.taskDescription)"
            logger.error("finalize: \(error)")
            onProgress?(.failed(phase: "finalize", error: error))
            return Result(success: false, message: error)
        }

        let stepIndex = (Int(step.id) ?? 0) + 1
        let totalSteps = codeSteps.count
        let completedCount = codeSteps.filter { $0.isCompleted }.count

        if options.dryRun {
            return try await runDry(
                options: options,
                repoDir: repoDir,
                stepIndex: stepIndex,
                totalSteps: totalSteps,
                completedCount: completedCount,
                onProgress: onProgress
            )
        }

        try await pipelineSource.markStepCompleted(step)
        try await git.add(files: [specURL.path], workingDirectory: repoDir)
        let specStaged = try await git.diffCachedNames(workingDirectory: repoDir)
        if !specStaged.isEmpty {
            try await git.commit(message: "Mark task \(stepIndex) as complete in spec.md", workingDirectory: repoDir)
        }

        // Push branch
        try await git.push(remote: "origin", branch: options.branchName, setUpstream: true, force: true, workingDirectory: repoDir)

        let repoSlug = await ChainPRHelpers.detectRepo(workingDirectory: repoDir, git: git)

        // Create draft PR
        let prTitle = ChainPRHelpers.buildPRTitle(projectName: options.projectName, task: options.taskDescription)
        let prBody = "Task \(stepIndex)/\(totalSteps): \(options.taskDescription)"
        var prCreateArgs = [
            "pr", "create",
            "--draft",
            "--title", prTitle,
            "--body", prBody,
            "--label", Constants.defaultPRLabel,
            "--head", options.branchName,
            "--base", options.baseBranch,
        ]
        if !repoSlug.isEmpty {
            prCreateArgs += ["--repo", repoSlug]
        }
        for assignee in projectConfig?.assignees ?? [] {
            prCreateArgs += ["--assignee", assignee]
        }
        for reviewer in projectConfig?.reviewers ?? [] {
            prCreateArgs += ["--reviewer", reviewer]
        }
        let prURL: String
        do {
            prURL = try GitHubOperations.runGhCommand(args: prCreateArgs)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            guard error.localizedDescription.contains("already exists") else { throw error }
            var prViewURLArgs = ["pr", "view", options.branchName, "--json", "url", "--jq", ".url"]
            if !repoSlug.isEmpty { prViewURLArgs += ["--repo", repoSlug] }
            prURL = try GitHubOperations.runGhCommand(args: prViewURLArgs)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var prViewArgs = ["pr", "view", options.branchName, "--json", "number"]
        if !repoSlug.isEmpty { prViewArgs += ["--repo", repoSlug] }
        let prViewOutput = try GitHubOperations.runGhCommand(args: prViewArgs)
        let prNumber = ChainPRHelpers.parsePRNumber(from: prViewOutput)

        if let prNumber {
            onProgress?(.prCreated(prNumber: prNumber, prURL: prURL))
        }

        // Generate PR summary
        onProgress?(.generatingSummary)
        var summaryContent: String?
        var summaryCost = 0.0

        do {
            let summaryPrompt = """
            You are reviewing a pull request. Analyze the changes made by running \
            `git diff \(options.baseBranch)...HEAD` and write a concise markdown summary.

            The task was: \(options.taskDescription)

            Write a PR summary that includes:
            1. A brief overview of what was changed
            2. Key implementation decisions
            3. Any notable patterns or conventions followed

            Output ONLY the markdown summary text, nothing else.
            """
            let summaryOptions = AIClientOptions(
                dangerouslySkipPermissions: true,
                workingDirectory: options.repoPath.path
            )
            let summaryText = TextAccumulator()
            _ = try await client.run(
                prompt: summaryPrompt,
                options: summaryOptions,
                onOutput: nil,
                onStreamEvent: { event in
                    if case .textDelta(let text) = event {
                        summaryText.text += text
                    }
                    onProgress?(.summaryStreamEvent(event))
                }
            )
            summaryContent = summaryText.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if summaryContent?.isEmpty == true { summaryContent = nil }
            logger.debug("summary: collected \(summaryText.text.count) chars of text")
            summaryCost = ChainPRHelpers.extractCost()
            if let summary = summaryContent, !summary.isEmpty {
                onProgress?(.summaryCompleted(summary: summary))
            }
        } catch {
            // Summary generation is non-fatal
        }

        // Post PR comment
        if let prNumber {
            onProgress?(.postingPRComment)
            do {
                let costBreakdown = CostBreakdown(mainCost: 0.0, reviewCost: 0.0, summaryCost: summaryCost)
                let report = PullRequestCreatedReport(
                    prNumber: prNumber,
                    prURL: prURL,
                    projectName: options.projectName,
                    task: options.taskDescription,
                    costBreakdown: costBreakdown,
                    repo: repoSlug,
                    runID: "",
                    summaryContent: summaryContent,
                    progressInfo: [
                        "tasks_completed": completedCount + 1,
                        "tasks_total": totalSteps,
                    ]
                )

                let formatter = MarkdownReportFormatter()
                let comment = formatter.format(report.buildCommentElements())

                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("pr_comment_\(UUID().uuidString).md")
                try comment.write(to: tempURL, atomically: true, encoding: String.Encoding.utf8)
                defer { try? FileManager.default.removeItem(at: tempURL) }

                var commentArgs = ["pr", "comment", prNumber, "--body-file", tempURL.path]
                if !repoSlug.isEmpty { commentArgs += ["--repo", repoSlug] }
                _ = try GitHubOperations.runGhCommand(args: commentArgs)
                onProgress?(.prCommentPosted)
            } catch {
                // Comment posting is non-fatal
            }
        }

        onProgress?(.completed(prURL: prURL.isEmpty ? nil : prURL))

        return Result(
            success: true,
            message: "PR created: \(options.taskDescription)",
            prURL: prURL.isEmpty ? nil : prURL,
            prNumber: prNumber,
            taskDescription: options.taskDescription
        )
    }

    private func runDry(
        options: Options,
        repoDir: String,
        stepIndex: Int,
        totalSteps: Int,
        completedCount: Int,
        onProgress: (@Sendable (Progress) -> Void)?
    ) async throws -> Result {
        logger.debug("dry-run: generating summary for task \(stepIndex)/\(totalSteps)")
        onProgress?(.generatingSummary)

        let summaryPrompt = """
        You are reviewing a pull request. Analyze the changes made by running \
        `git diff \(options.baseBranch)...HEAD` and write a concise markdown summary.

        The task was: \(options.taskDescription)

        Write a PR summary that includes:
        1. A brief overview of what was changed
        2. Key implementation decisions
        3. Any notable patterns or conventions followed

        Output ONLY the markdown summary text, nothing else.
        """
        let summaryOptions = AIClientOptions(
            dangerouslySkipPermissions: true,
            workingDirectory: options.repoPath.path
        )

        var summaryContent: String?
        do {
            let summaryText = TextAccumulator()
            _ = try await client.run(
                prompt: summaryPrompt,
                options: summaryOptions,
                onOutput: nil,
                onStreamEvent: { event in
                    if case .textDelta(let text) = event {
                        summaryText.text += text
                    }
                    onProgress?(.summaryStreamEvent(event))
                }
            )
            let collected = summaryText.text.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.debug("dry-run: collected \(summaryText.text.count) chars; preview: \(String(collected.prefix(500)))")
            summaryContent = collected.isEmpty ? nil : collected
            if let summary = summaryContent {
                onProgress?(.summaryCompleted(summary: summary))
            }
        } catch {
            logger.error("dry-run: summary generation failed: \(error)")
        }

        let repoSlug = await ChainPRHelpers.detectRepo(workingDirectory: repoDir, git: git)
        let costBreakdown = CostBreakdown(mainCost: 0.0, reviewCost: 0.0, summaryCost: 0.0)
        let report = PullRequestCreatedReport(
            prNumber: "DRY-RUN",
            prURL: "https://github.com/\(repoSlug)/pull/DRY-RUN",
            projectName: options.projectName,
            task: options.taskDescription,
            costBreakdown: costBreakdown,
            repo: repoSlug,
            runID: "",
            summaryContent: summaryContent,
            progressInfo: [
                "tasks_completed": completedCount + 1,
                "tasks_total": totalSteps,
            ]
        )
        let formatter = MarkdownReportFormatter()
        let comment = formatter.format(report.buildCommentElements())

        logger.debug("dry-run: formatted PR comment (\(comment.count) chars):\n\(comment)")
        onProgress?(.completed(prURL: nil))

        return Result(
            success: true,
            message: "[DRY RUN] PR comment preview generated (not posted)",
            prURL: nil,
            prNumber: nil,
            taskDescription: options.taskDescription
        )
    }
}
