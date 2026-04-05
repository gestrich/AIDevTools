import AIOutputSDK
import ClaudeChainSDK
import ClaudeChainService
import CredentialService
import Foundation
import GitSDK
import Logging
import PipelineSDK
import UseCaseSDK

public struct RunSpecChainTaskUseCase: UseCase {

    public struct Options: Sendable {
        public let baseBranch: String
        public let dryRun: Bool
        public let projectName: String
        public let repoPath: URL
        public let stagingOnly: Bool
        public let taskIndex: Int?

        public init(
            repoPath: URL,
            projectName: String,
            baseBranch: String,
            taskIndex: Int? = nil,
            stagingOnly: Bool = false,
            dryRun: Bool = false
        ) {
            self.baseBranch = baseBranch
            self.dryRun = dryRun
            self.projectName = projectName
            self.repoPath = repoPath
            self.stagingOnly = stagingOnly
            self.taskIndex = taskIndex
        }
    }

    public struct Result: Sendable {
        public let branchName: String?
        public let isStagingOnly: Bool
        public let message: String
        public let phasesCompleted: Int
        public let prNumber: String?
        public let prURL: String?
        public let success: Bool
        public let taskDescription: String?

        public init(
            success: Bool,
            message: String,
            branchName: String? = nil,
            isStagingOnly: Bool = false,
            prURL: String? = nil,
            prNumber: String? = nil,
            taskDescription: String? = nil,
            phasesCompleted: Int = 0
        ) {
            self.branchName = branchName
            self.isStagingOnly = isStagingOnly
            self.message = message
            self.phasesCompleted = phasesCompleted
            self.prNumber = prNumber
            self.prURL = prURL
            self.success = success
            self.taskDescription = taskDescription
        }
    }

    public enum Progress: Sendable {
        case aiCompleted
        case aiOutput(String)
        case aiStreamEvent(AIStreamEvent)
        case completed(prURL: String?)
        case failed(phase: String, error: String)
        case finalizing
        case generatingSummary
        case postingPRComment
        case postScriptCompleted(ActionResult)
        case prCommentPosted
        case prCreated(prNumber: String, prURL: String)
        case preparingProject
        case preparedTask(description: String, index: Int, total: Int)
        case preScriptCompleted(ActionResult)
        case reviewCompleted(summary: String)
        case runningAI(taskDescription: String)
        case runningPostScript
        case runningPreScript
        case runningReview
        case summaryCompleted(summary: String)
        case summaryStreamEvent(AIStreamEvent)
    }

    private let client: any AIClient
    private let git: GitClient
    private let logger = Logger(label: "RunSpecChainTaskUseCase")

    public init(client: any AIClient, git: GitClient = GitClient()) {
        self.client = client
        self.git = git
    }

    public func run(
        options: Options,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> Result {
        var phasesCompleted = 0

        // Phase 1: Prepare — load project via source, derive local paths
        onProgress?(.preparingProject)
        logger.debug("prepare: project=\(options.projectName) repoPath=\(options.repoPath.path) stagingOnly=\(options.stagingOnly)")

        let source = MarkdownClaudeChainSource(
            projectName: options.projectName,
            repoPath: options.repoPath,
            git: git,
            taskIndex: options.taskIndex
        )

        let chainProject = try await source.loadProject()
        let projectBasePath = URL(fileURLWithPath: chainProject.specPath).deletingLastPathComponent().path
        let chainDir = URL(fileURLWithPath: projectBasePath).deletingLastPathComponent().path
        let project = Project(name: options.projectName, basePath: projectBasePath)
        let specURL = URL(fileURLWithPath: project.specPath)
        let githubClient = GitHubClient(workingDirectory: chainDir)
        let repository = ProjectRepository(repo: "", gitHubOperations: GitHubOperations(githubClient: githubClient))
        let projectConfig = try? repository.loadLocalConfiguration(project: project)

        let baseBranch = options.baseBranch
        let repoDir = options.repoPath.path
        logger.debug("prepare: baseBranch=\(baseBranch) repoDir=\(repoDir)")

        // Best-effort fetch so spec.md reflects the latest remote state; continue on failure
        logger.debug("prepare: fetching origin/\(baseBranch)")
        if let _ = try? await git.fetch(remote: "origin", branch: baseBranch, workingDirectory: repoDir) {
            logger.debug("prepare: fetch complete, checking out FETCH_HEAD")
            try? await git.checkout(ref: "FETCH_HEAD", workingDirectory: repoDir)
        } else {
            logger.debug("prepare: fetch failed, continuing with local spec.md")
        }

        guard let task = try await source.nextTask() else {
            let errorMessage = chainProject.totalTasks == 0
                ? "No spec.md found for project \(options.projectName)"
                : "All tasks completed for project \(options.projectName)"
            logger.error("prepare: \(errorMessage)")
            onProgress?(.failed(phase: "prepare", error: errorMessage))
            return Result(success: false, message: errorMessage)
        }

        let matchedChainTask = chainProject.tasks.first(where: {
            TaskService.generateTaskHash(description: $0.description) == task.id
        })
        let taskDescription = matchedChainTask?.description ?? task.id
        let stepIndex = matchedChainTask?.index ?? 1
        let totalSteps = chainProject.totalTasks
        let completedCount = chainProject.completedTasks
        logger.debug("prepare: selected task id=\(task.id) description=\(taskDescription)")

        onProgress?(.preparedTask(description: taskDescription, index: stepIndex, total: totalSteps))
        phasesCompleted += 1

        let repoSlug = await ChainPRHelpers.detectRepo(workingDirectory: repoDir, git: git)

        // Check capacity before creating branch so no branch is created when at the PR limit
        if !options.stagingOnly, let projectConfig, !repoSlug.isEmpty {
            let prService = PRService(repo: repoSlug)
            let assigneeService = AssigneeService(repo: repoSlug, prService: prService)
            let capacityResult = assigneeService.checkCapacity(
                config: projectConfig,
                label: Constants.defaultPRLabel,
                project: options.projectName
            )
            guard capacityResult.hasCapacity else {
                throw RunSpecChainTaskError.capacityExceeded(
                    project: options.projectName,
                    openCount: capacityResult.openPRs.count,
                    maxOpen: capacityResult.maxOpenPRs
                )
            }
        }

        // Create feature branch (already on baseBranch from earlier checkout)
        let branchName = chainProject.branchPrefix + task.id
        try await git.checkout(ref: branchName, forceCreate: true, workingDirectory: repoDir)

        // Phase 2: Pre-action script
        onProgress?(.runningPreScript)
        let preResult = try ScriptRunner.runActionScript(
            projectPath: project.basePath,
            scriptType: "pre",
            workingDirectory: options.repoPath.path
        )
        onProgress?(.preScriptCompleted(preResult))
        phasesCompleted += 1

        // Phase 3: AI execution
        onProgress?(.runningAI(taskDescription: taskDescription))

        let aiOptions = AIClientOptions(
            dangerouslySkipPermissions: true,
            workingDirectory: options.repoPath.path
        )

        let mainAccumulator = StreamAccumulator()
        let aiResult = try await client.run(
            prompt: task.instructions,
            options: aiOptions,
            onOutput: { text in
                onProgress?(.aiOutput(text))
            },
            onStreamEvent: { event in
                _ = mainAccumulator.apply(event)
                onProgress?(.aiStreamEvent(event))
            }
        )
        onProgress?(.aiCompleted)
        phasesCompleted += 1

        let mainCost = mainAccumulator.blocks.compactMap {
            if case .metrics(_, let cost, _) = $0 { return cost } else { return nil }
        }.last ?? 0.0

        // Phase 4: Post-action script
        onProgress?(.runningPostScript)
        let postResult = try ScriptRunner.runActionScript(
            projectPath: project.basePath,
            scriptType: "post",
            workingDirectory: options.repoPath.path
        )
        onProgress?(.postScriptCompleted(postResult))
        phasesCompleted += 1

        // Phase 5: Finalize — commit, push, create PR
        onProgress?(.finalizing)

        // Commit any uncommitted changes from the AI run
        let statusLines = try await git.status(workingDirectory: repoDir)
        if !statusLines.isEmpty {
            try await git.addAll(workingDirectory: repoDir)
            let stagedFiles = try await git.diffCachedNames(workingDirectory: repoDir)
            if !stagedFiles.isEmpty {
                try await git.commit(message: "Complete task: \(taskDescription)", workingDirectory: repoDir)
            }
        }

        // When staging only, stop here — do not update spec.md, push, or create a PR
        if options.stagingOnly {
            onProgress?(.completed(prURL: nil))
            return Result(
                success: true,
                message: "Task staged locally (no PR created): \(taskDescription)",
                branchName: branchName,
                isStagingOnly: true,
                taskDescription: taskDescription,
                phasesCompleted: phasesCompleted
            )
        }

        // Mark task complete and commit spec.md
        try await source.markComplete(task)
        try await git.add(files: [specURL.path], workingDirectory: repoDir)
        let specStagedFiles = try await git.diffCachedNames(workingDirectory: repoDir)
        if !specStagedFiles.isEmpty {
            try await git.commit(message: "Mark task \(stepIndex) as complete in spec.md", workingDirectory: repoDir)
        }

        // Phase 5b: Review pass (runs only if review.md exists)
        var reviewCost = 0.0
        if let reviewContent = try? repository.loadLocalReview(project: project) {
            onProgress?(.runningReview)

            let reviewPrompt = buildReviewPrompt(
                taskDescription: taskDescription,
                specPath: project.specPath,
                reviewContent: reviewContent
            )
            let reviewOptions = AIClientOptions(
                dangerouslySkipPermissions: true,
                workingDirectory: options.repoPath.path
            )
            let reviewSchema = """
            {"type":"object","properties":{"commitMessage":{"type":"string"},"summary":{"type":"string"}},"required":["commitMessage","summary"]}
            """
            let reviewResult = try await client.runStructured(
                ReviewOutput.self,
                prompt: reviewPrompt,
                jsonSchema: reviewSchema,
                options: reviewOptions,
                onOutput: { text in onProgress?(.aiOutput(text)) },
                onStreamEvent: { event in onProgress?(.aiStreamEvent(event)) }
            )

            let reviewStatus = try await git.status(workingDirectory: repoDir)
            if !reviewStatus.isEmpty {
                try await git.addAll(workingDirectory: repoDir)
                let staged = try await git.diffCachedNames(workingDirectory: repoDir)
                if !staged.isEmpty {
                    try await git.commit(message: reviewResult.value.commitMessage, workingDirectory: repoDir)
                }
            }

            let reviewSummary = reviewResult.value.summary
            appendReviewNote(specPath: project.specPath, taskDescription: taskDescription, summary: reviewSummary)
            try await git.add(files: [specURL.path], workingDirectory: repoDir)
            try await git.commit(message: "Add review note for task \(stepIndex)", workingDirectory: repoDir)

            onProgress?(.reviewCompleted(summary: reviewSummary))
        }

        // Push branch
        try await git.push(remote: "origin", branch: branchName, setUpstream: true, force: true, workingDirectory: repoDir)

        // Create draft PR
        let prTitle = ChainPRHelpers.buildPRTitle(projectName: options.projectName, task: taskDescription)
        let prBody = "Task \(stepIndex)/\(totalSteps): \(taskDescription)"
        var prCreateArgs = [
            "pr", "create",
            "--draft",
            "--title", prTitle,
            "--body", prBody,
            "--label", Constants.defaultPRLabel,
            "--head", branchName,
            "--base", baseBranch,
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
            var prViewURLArgs = ["pr", "view", branchName, "--json", "url", "--jq", ".url"]
            if !repoSlug.isEmpty { prViewURLArgs += ["--repo", repoSlug] }
            prURL = try GitHubOperations.runGhCommand(args: prViewURLArgs)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Get PR number
        var prViewArgs = [
            "pr", "view", branchName,
            "--json", "number",
        ]
        if !repoSlug.isEmpty {
            prViewArgs += ["--repo", repoSlug]
        }
        let prViewOutput = try GitHubOperations.runGhCommand(args: prViewArgs)
        let prNumber = ChainPRHelpers.parsePRNumber(from: prViewOutput)

        if let prNumber {
            onProgress?(.prCreated(prNumber: prNumber, prURL: prURL))
        }
        phasesCompleted += 1

        // Phase 6: Generate PR summary
        onProgress?(.generatingSummary)
        var summaryContent: String?
        var summaryCost = 0.0

        do {
            let summaryPrompt = buildSummaryPrompt(
                taskDescription: taskDescription,
                baseBranch: baseBranch
            )
            let summaryOptions = AIClientOptions(
                dangerouslySkipPermissions: true,
                workingDirectory: options.repoPath.path
            )

            let summaryAccumulator = StreamAccumulator()
            _ = try await client.run(
                prompt: summaryPrompt,
                options: summaryOptions,
                onOutput: nil,
                onStreamEvent: { event in
                    _ = summaryAccumulator.apply(event)
                    onProgress?(.summaryStreamEvent(event))
                }
            )
            let summaryText = summaryAccumulator.blocks.compactMap {
                if case .text(let t) = $0 { return t } else { return nil }
            }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            summaryContent = summaryText.isEmpty ? nil : summaryText
            logger.debug("summary: collected \(summaryText.count) chars of text")
            summaryCost = summaryAccumulator.blocks.compactMap {
                if case .metrics(_, let cost, _) = $0 { return cost } else { return nil }
            }.last ?? 0.0
            if let summary = summaryContent, !summary.isEmpty {
                onProgress?(.summaryCompleted(summary: summary))
            }
        } catch {
            logger.warning("summary generation failed: \(error)")
        }
        phasesCompleted += 1

        // Phase 7: Post PR comment
        if let prNumber {
            onProgress?(.postingPRComment)
            do {
                let costBreakdown = CostBreakdown(
                    mainCost: mainCost,
                    reviewCost: reviewCost,
                    summaryCost: summaryCost
                )
                let report = PullRequestCreatedReport(
                    prNumber: prNumber,
                    prURL: prURL,
                    projectName: options.projectName,
                    task: taskDescription,
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

                if options.dryRun {
                    print("\n=== PR Comment Preview ===")
                    print(comment)
                    print("=== End PR Comment Preview ===\n")
                } else {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("pr_comment_\(UUID().uuidString).md")
                    try comment.write(to: tempURL, atomically: true, encoding: .utf8)
                    defer { try? FileManager.default.removeItem(at: tempURL) }

                    var commentArgs = [
                        "pr", "comment", prNumber,
                        "--body-file", tempURL.path,
                    ]
                    if !repoSlug.isEmpty {
                        commentArgs += ["--repo", repoSlug]
                    }
                    _ = try GitHubOperations.runGhCommand(args: commentArgs)
                    onProgress?(.prCommentPosted)
                }
            } catch {
                logger.warning("PR comment posting failed: \(error)")
            }
            phasesCompleted += 1
        }

        onProgress?(.completed(prURL: prURL.isEmpty ? nil : prURL))

        return Result(
            success: true,
            message: "Task completed: \(taskDescription)",
            prURL: prURL.isEmpty ? nil : prURL,
            prNumber: prNumber,
            taskDescription: taskDescription,
            phasesCompleted: phasesCompleted
        )
    }

    // MARK: - Prompt Building

    private func buildReviewPrompt(taskDescription: String, specPath: String, reviewContent: String) -> String {
        """
        You are in the middle of running the task chain for spec.md at \(specPath).

        The last task was just completed and committed: "\(taskDescription)"

        Your job is to review those changes and apply improvements based on the criteria in review.md below.
        You should err on the side of making changes for conformance, rather than just verifying things are done.
        Even things that are slightly not right should be fixed. Err on the side of improving the work that was done.

        --- BEGIN review.md ---
        \(reviewContent)
        --- END review.md ---

        After completing your review and making any changes, respond with JSON containing:
        - commitMessage: a short commit message describing what you changed (or "No review changes" if nothing changed)
        - summary: a one-line description of the review findings for the spec.md annotation
        """
    }

    private func buildSummaryPrompt(taskDescription: String, baseBranch: String) -> String {
        """
        You are reviewing a pull request. Analyze the changes made by running \
        `git diff \(baseBranch)...HEAD` and write a concise markdown summary.

        The task was: \(taskDescription)

        Write a PR summary that includes:
        1. A brief overview of what was changed
        2. Key implementation decisions
        3. Any notable patterns or conventions followed

        Output ONLY the markdown summary text, nothing else.
        """
    }

    // MARK: - Helpers

    public func appendReviewNote(specPath: String, taskDescription: String, summary: String) {
        guard var content = try? String(contentsOfFile: specPath, encoding: .utf8) else { return }
        let taskLine = "- [x] \(taskDescription)"
        guard let range = content.range(of: taskLine) else { return }
        let insertionIndex = content.index(after: content[range.upperBound...].firstIndex(of: "\n") ?? content.endIndex)
        let note = "  <!-- review: \(summary) -->\n"
        content.insert(contentsOf: note, at: insertionIndex)
        try? content.write(toFile: specPath, atomically: true, encoding: .utf8)
    }

}

private struct ReviewOutput: Decodable, Sendable {
    let commitMessage: String
    let summary: String
}

public enum RunSpecChainTaskError: LocalizedError {
    case capacityExceeded(project: String, openCount: Int, maxOpen: Int)

    public var errorDescription: String? {
        switch self {
        case .capacityExceeded(let project, let openCount, let maxOpen):
            return "Project '\(project)' is at capacity: \(openCount)/\(maxOpen) async slots in use. Cannot create PR."
        }
    }
}
