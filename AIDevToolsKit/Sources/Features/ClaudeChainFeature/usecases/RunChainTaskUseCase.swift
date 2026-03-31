import AIOutputSDK
import ClaudeChainSDK
import ClaudeChainService
import CredentialService
import Foundation
import GitSDK
import PipelineSDK
import UseCaseSDK

public struct RunChainTaskUseCase: UseCase {

    public struct Options: Sendable {
        public let projectName: String
        public let repoPath: URL

        public init(repoPath: URL, projectName: String) {
            self.projectName = projectName
            self.repoPath = repoPath
        }
    }

    public struct Result: Sendable {
        public let message: String
        public let phasesCompleted: Int
        public let prNumber: String?
        public let prURL: String?
        public let success: Bool
        public let taskDescription: String?

        public init(
            success: Bool,
            message: String,
            prURL: String? = nil,
            prNumber: String? = nil,
            taskDescription: String? = nil,
            phasesCompleted: Int = 0
        ) {
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
        case runningAI(taskDescription: String)
        case runningPostScript
        case runningPreScript
        case summaryCompleted(summary: String)
        case summaryStreamEvent(AIStreamEvent)
    }

    private let client: any AIClient
    private let git: GitClient

    public init(client: any AIClient, git: GitClient = GitClient()) {
        self.client = client
        self.git = git
    }

    public func run(
        options: Options,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> Result {
        var phasesCompleted = 0

        // Phase 1: Prepare — load project config, then use MarkdownPipelineSource to find next task
        onProgress?(.preparingProject)

        let chainDir = options.repoPath.appendingPathComponent("claude-chain").path
        let project = Project(
            name: options.projectName,
            basePath: (chainDir as NSString).appendingPathComponent(options.projectName)
        )
        let githubClient = GitHubClient(workingDirectory: chainDir)
        let repository = ProjectRepository(repo: "", gitHubOperations: GitHubOperations(githubClient: githubClient))

        let config = (try? repository.loadLocalConfiguration(project: project))
            ?? ProjectConfiguration.default(project: project)

        let baseBranch = config.getBaseBranch(defaultBaseBranch: Constants.defaultBaseBranch)
        let repoDir = options.repoPath.path

        // Fetch and checkout base branch so spec.md reflects the latest remote state
        try await git.fetch(remote: "origin", branch: baseBranch, workingDirectory: repoDir)
        try await git.checkout(ref: "FETCH_HEAD", workingDirectory: repoDir)

        // Load spec content for prompt building
        guard let spec = try repository.loadLocalSpec(project: project) else {
            onProgress?(.failed(phase: "prepare", error: "No spec.md found for project \(options.projectName)"))
            return Result(
                success: false,
                message: "No spec.md found for project \(options.projectName)"
            )
        }

        // Use MarkdownPipelineSource (.task format) to discover the next pending task
        let specURL = URL(fileURLWithPath: project.specPath)
        let pipelineSource = MarkdownPipelineSource(fileURL: specURL, format: .task, appendCreatePRStep: false)
        let pipeline = try await pipelineSource.load()
        let codeSteps = pipeline.steps.compactMap { $0 as? CodeChangeStep }

        guard let nextStep = codeSteps.first(where: { !$0.isCompleted }) else {
            onProgress?(.failed(phase: "prepare", error: "All tasks completed for project \(options.projectName)"))
            return Result(
                success: false,
                message: "All tasks completed for project \(options.projectName)"
            )
        }

        let stepIndex = (Int(nextStep.id) ?? 0) + 1
        let totalSteps = codeSteps.count
        let completedCount = codeSteps.filter { $0.isCompleted }.count

        onProgress?(.preparedTask(description: nextStep.description, index: stepIndex, total: totalSteps))
        phasesCompleted += 1

        // Create feature branch (already on baseBranch from earlier checkout)
        let taskHash = TaskService.generateTaskHash(description: nextStep.description)
        let branchName = PRService.formatBranchName(projectName: options.projectName, taskHash: taskHash)
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

        // Phase 3: AI execution — use step.description embedded in the full spec prompt
        let claudePrompt = buildTaskPrompt(taskDescription: nextStep.description, specContent: spec.content)
        onProgress?(.runningAI(taskDescription: nextStep.description))

        let aiOptions = AIClientOptions(
            dangerouslySkipPermissions: true,
            workingDirectory: options.repoPath.path
        )

        let aiResult = try await client.run(
            prompt: claudePrompt,
            options: aiOptions,
            onOutput: { text in
                onProgress?(.aiOutput(text))
            },
            onStreamEvent: { event in
                onProgress?(.aiStreamEvent(event))
            }
        )
        onProgress?(.aiCompleted)
        phasesCompleted += 1

        // Extract cost from AI stream metrics (captured from the last metrics event)
        let mainCost = extractCost(from: aiResult)

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
                try await git.commit(message: "Complete task: \(nextStep.description)", workingDirectory: repoDir)
            }
        }

        // Mark task complete via MarkdownPipelineSource (unified pipeline persistence)
        try await pipelineSource.markStepCompleted(nextStep)
        try await git.add(files: [specURL.path], workingDirectory: repoDir)
        let specStagedFiles = try await git.diffCachedNames(workingDirectory: repoDir)
        if !specStagedFiles.isEmpty {
            try await git.commit(message: "Mark task \(stepIndex) as complete in spec.md", workingDirectory: repoDir)
        }

        // Push branch
        try await git.push(remote: "origin", branch: branchName, setUpstream: true, force: true, workingDirectory: repoDir)

        let repoSlug = await detectRepo(workingDirectory: repoDir)

        // Create draft PR
        let prTitle = buildPRTitle(projectName: options.projectName, task: nextStep.description)
        let prBody = "Task \(stepIndex)/\(totalSteps): \(nextStep.description)"
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
        let prNumber = parsePRNumber(from: prViewOutput)

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
                taskDescription: nextStep.description,
                baseBranch: baseBranch
            )
            let summaryOptions = AIClientOptions(
                dangerouslySkipPermissions: true,
                workingDirectory: options.repoPath.path
            )

            let summaryResult = try await client.run(
                prompt: summaryPrompt,
                options: summaryOptions,
                onOutput: nil,
                onStreamEvent: { event in
                    onProgress?(.summaryStreamEvent(event))
                }
            )
            summaryContent = summaryResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            summaryCost = extractCost(from: summaryResult)
            if let summary = summaryContent, !summary.isEmpty {
                onProgress?(.summaryCompleted(summary: summary))
            }
        } catch {
            // Summary generation is non-fatal
        }
        phasesCompleted += 1

        // Phase 7: Post PR comment
        if let prNumber {
            onProgress?(.postingPRComment)
            do {
                let costBreakdown = CostBreakdown(
                    mainCost: mainCost,
                    summaryCost: summaryCost
                )
                let report = PullRequestCreatedReport(
                    prNumber: prNumber,
                    prURL: prURL,
                    projectName: options.projectName,
                    task: nextStep.description,
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
            } catch {
                // Comment posting is non-fatal
            }
            phasesCompleted += 1
        }

        onProgress?(.completed(prURL: prURL.isEmpty ? nil : prURL))

        return Result(
            success: true,
            message: "Task completed: \(nextStep.description)",
            prURL: prURL.isEmpty ? nil : prURL,
            prNumber: prNumber,
            taskDescription: nextStep.description,
            phasesCompleted: phasesCompleted
        )
    }

    // MARK: - Prompt Building

    private func buildTaskPrompt(taskDescription: String, specContent: String) -> String {
        """
        Complete the following task from spec.md:

        Task: \(taskDescription)

        Instructions: Read the entire spec.md file below to understand both WHAT to do and HOW to do it. \
        Follow all guidelines and patterns specified in the document.

        --- BEGIN spec.md ---
        \(specContent)
        --- END spec.md ---

        Now complete the task '\(taskDescription)' following all the details and instructions in the spec.md file above.
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

    private func buildPRTitle(projectName: String, task: String) -> String {
        let maxTitleLength = 80
        let titlePrefix = "ClaudeChain: [\(projectName)] "
        let availableForTask = maxTitleLength - titlePrefix.count
        let truncatedTask: String
        if task.count > availableForTask {
            truncatedTask = String(task.prefix(availableForTask - 3)) + "..."
        } else {
            truncatedTask = task
        }
        return "\(titlePrefix)\(truncatedTask)"
    }

    // MARK: - Helpers

    private func extractCost(from result: AIClientResult) -> Double {
        // Cost is typically reported in stderr as part of Claude CLI output
        // For now, return 0.0 — the cost will be populated when metrics events are available
        return 0.0
    }

    private func parsePRNumber(from jsonOutput: String) -> String? {
        guard let data = jsonOutput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = json["number"] as? Int else {
            return nil
        }
        return String(number)
    }

    private func detectRepo(workingDirectory: String) async -> String {
        if let repo = ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"], !repo.isEmpty {
            return repo
        }
        guard let remoteURL = try? await git.remoteGetURL(workingDirectory: workingDirectory) else {
            return ""
        }
        guard remoteURL.contains("github.com") else {
            return ""
        }
        return remoteURL
            .replacingOccurrences(of: "git@github.com:", with: "")
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: ".git", with: "")
    }
}
