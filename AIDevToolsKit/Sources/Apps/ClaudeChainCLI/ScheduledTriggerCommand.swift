import ArgumentParser
import ClaudeChainFeature
import ClaudeChainSDK
import ClaudeChainService
import ClaudeCLISDK
import CredentialFeature
import DataPathsService
import Foundation
import GitHubService

public struct ScheduledTriggerCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "scheduled-trigger",
        abstract: "Trigger available Claude Chain projects up to a global limit"
    )

    @Option(name: .long, help: "GitHub repository (owner/name)")
    public var repo: String?

    @Option(name: .long, help: "Path to the checked-out repository")
    public var repoPath: String?

    @Option(name: .long, help: "Maximum number of workflow triggers to dispatch")
    public var maxTriggers: Int = 5

    @Option(name: .long, help: "PR label used for capacity checks")
    public var label: String?

    @Option(name: .long, help: "Workflow file name to dispatch")
    public var workflowFile: String = Self.defaultWorkflowFile

    private static let defaultWorkflowFile = "claude-chain.yml"

    public init() {}

    public func run() async throws {
        guard maxTriggers >= 0 else {
            throw ValidationError("--max-triggers must be greater than or equal to 0")
        }

        let repo = try resolveRepository()
        let repoURL = resolveRepositoryURL()
        let label = resolveLabel()

        let gh = GitHubActions()
        let dataRoot = ResolveDataPathUseCase().resolve().path
        let dataPathsService = try DataPathsService(rootPath: dataRoot)
        let resolver = resolveGitHubCredentials(githubProfileId: nil, githubToken: nil)

        let prService = PRService(repo: repo)
        let assigneeService = AssigneeService(repo: repo, prService: prService)
        let gitHubPRService = try await GitHubServiceFactory.createPRService(
            repoPath: repoURL.path,
            resolver: resolver,
            dataPathsService: dataPathsService
        )
        let chainService = ClaudeChainService(client: ClaudeProvider(), repoPath: repoURL, prService: gitHubPRService)
        let workflowService = try makeWorkflowService(repo: repo)
        let projectRepository = ProjectRepository(repo: repo)

        let chainResult = try await chainService.listChains(source: ChainSource.remote)
        for failure in chainResult.failures {
            fputs("Warning: \(failure.localizedDescription)\n", stderr)
        }

        let allProjects = chainResult.projects.sorted { $0.name < $1.name }
        let pendingProjects = allProjects.filter { $0.pendingTasks > 0 }
        var projectResults: [ProjectRunResult] = allProjects
            .filter { $0.pendingTasks == 0 }
            .map { ProjectRunResult(projectName: $0.name, status: .noPendingTasks) }

        var remainingBudget = maxTriggers
        var pendingIndex = 0
        while pendingIndex < pendingProjects.count {
            if remainingBudget == 0 {
                for project in pendingProjects[pendingIndex...] {
                    projectResults.append(ProjectRunResult(projectName: project.name, status: .globalMaxReached))
                }
                break
            }

            let project = pendingProjects[pendingIndex]
            let localProject = Project(
                name: project.name,
                basePath: repoURL.appendingPathComponent(project.basePath).path
            )
            let config = try projectRepository.loadLocalConfiguration(project: localProject)
            let capacityResult = assigneeService.checkCapacity(config: config, label: label, project: project.name)
            let slotsAvailable = max(0, capacityResult.maxOpenPRs - capacityResult.openCount)

            if slotsAvailable == 0 {
                projectResults.append(
                    ProjectRunResult(
                        projectName: project.name,
                        status: .atCapacity(openCount: capacityResult.openCount, maxOpenPRs: capacityResult.maxOpenPRs)
                    )
                )
                pendingIndex += 1
                continue
            }

            let triggersForProject = min(2, slotsAvailable, remainingBudget)
            var successfulTriggers = 0
            var failureMessages: [String] = []

            for _ in 0..<triggersForProject {
                do {
                    try await workflowService.triggerClaudeChainWorkflow(
                        projectName: project.name,
                        baseBranch: project.baseBranch,
                        checkoutRef: "HEAD",
                        workflowFileName: workflowFile
                    )
                    successfulTriggers += 1
                    remainingBudget -= 1
                } catch {
                    failureMessages.append(String(describing: error))
                }
            }

            projectResults.append(
                ProjectRunResult(
                    projectName: project.name,
                    status: .triggerAttempted(
                        successful: successfulTriggers,
                        failed: failureMessages.count,
                        messages: failureMessages
                    )
                )
            )
            pendingIndex += 1
        }

        let summary = buildSummary(
            allProjects: allProjects,
            pendingProjects: pendingProjects,
            maxTriggers: maxTriggers,
            workflowFile: workflowFile,
            projectResults: projectResults.sorted { $0.projectName < $1.projectName },
            failures: chainResult.failures.map { $0.localizedDescription }
        )
        gh.writeStepSummary(text: summary)
        print(summary)
    }

    private func buildSummary(
        allProjects: [ChainProject],
        pendingProjects: [ChainProject],
        maxTriggers: Int,
        workflowFile: String,
        projectResults: [ProjectRunResult],
        failures: [String]
    ) -> String {
        let totals = SummaryTotals(results: projectResults)

        var lines: [String] = [
            "# Claude Chain Scheduled Trigger",
            "",
            "- Open chains found: \(allProjects.count)",
            "- Chains with pending tasks: \(pendingProjects.count)",
            "- Max triggers this run: \(maxTriggers)",
            "- Workflow file: `\(workflowFile)`",
            "",
            "## Project Results",
            ""
        ]

        for result in projectResults {
            lines.append("- `\(result.projectName)`: \(result.status.summary)")
        }

        lines.append("")
        lines.append("## Totals")
        lines.append("")
        lines.append("- Triggered: \(totals.triggered)")
        lines.append("- Identified but not triggered: \(totals.notTriggered)")
        lines.append("- Not triggered because at capacity: \(totals.atCapacity)")
        lines.append("- Not triggered because global max was reached: \(totals.globalMaxReached)")
        lines.append("- Not triggered because there were no pending tasks: \(totals.noPendingTasks)")
        lines.append("- Trigger attempts that failed: \(totals.failedAttempts)")

        if !failures.isEmpty {
            lines.append("")
            lines.append("## Warnings")
            lines.append("")
            for failure in failures.sorted() {
                lines.append("- \(failure)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func makeWorkflowService(repo: String) throws -> WorkflowService {
        let env = ProcessInfo.processInfo.environment
        guard let token = env["GH_TOKEN"] ?? env["GITHUB_TOKEN"] else {
            throw ValidationError("GH_TOKEN or GITHUB_TOKEN must be set")
        }

        let slugParts = repo.split(separator: "/", maxSplits: 1).map(String.init)
        guard slugParts.count == 2 else {
            throw ValidationError("Repository must be in owner/name format")
        }

        let service = GitHubServiceFactory.make(token: token, owner: slugParts[0], repo: slugParts[1])
        return WorkflowService(githubService: service)
    }

    private func resolveLabel() -> String {
        label
            ?? ProcessInfo.processInfo.environment["PR_LABEL"]
            ?? ClaudeChainConstants.defaultPRLabel
    }

    private func resolveRepository() throws -> String {
        if let repo, !repo.isEmpty {
            return repo
        }

        if let envRepo = ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"], !envRepo.isEmpty {
            return envRepo
        }

        throw ValidationError("--repo is required when GITHUB_REPOSITORY is not set")
    }

    private func resolveRepositoryURL() -> URL {
        let path = repoPath ?? FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
    }
}

private struct ProjectRunResult {
    let projectName: String
    let status: ProjectRunStatus
}

private enum ProjectRunStatus {
    case atCapacity(openCount: Int, maxOpenPRs: Int)
    case globalMaxReached
    case noPendingTasks
    case triggerAttempted(successful: Int, failed: Int, messages: [String])

    var failedAttempts: Int {
        switch self {
        case .triggerAttempted(_, let failed, _):
            return failed
        case .atCapacity, .globalMaxReached, .noPendingTasks:
            return 0
        }
    }

    var notTriggeredCount: Int {
        switch self {
        case .atCapacity, .globalMaxReached, .noPendingTasks:
            return 1
        case .triggerAttempted(let successful, _, _):
            return successful == 0 ? 1 : 0
        }
    }

    var successfulTriggers: Int {
        switch self {
        case .triggerAttempted(let successful, _, _):
            return successful
        case .atCapacity, .globalMaxReached, .noPendingTasks:
            return 0
        }
    }

    var summary: String {
        switch self {
        case .atCapacity(let openCount, let maxOpenPRs):
            return "skipped - at capacity (\(openCount)/\(maxOpenPRs) open PRs)"
        case .globalMaxReached:
            return "skipped - global max reached"
        case .noPendingTasks:
            return "no pending tasks"
        case .triggerAttempted(let successful, let failed, let messages):
            if failed == 0 {
                return "triggered \(successful) job\(successful == 1 ? "" : "s")"
            }
            if successful == 0 {
                let message = messages.first ?? "unknown error"
                return "trigger failed - \(message)"
            }
            let message = messages.first ?? "unknown error"
            return "triggered \(successful) job\(successful == 1 ? "" : "s"), \(failed) failed (\(message))"
        }
    }
}

private struct SummaryTotals {
    let atCapacity: Int
    let failedAttempts: Int
    let globalMaxReached: Int
    let noPendingTasks: Int
    let notTriggered: Int
    let triggered: Int

    init(results: [ProjectRunResult]) {
        self.atCapacity = results.filter {
            if case .atCapacity = $0.status { return true }
            return false
        }.count
        self.failedAttempts = results.reduce(0) { $0 + $1.status.failedAttempts }
        self.globalMaxReached = results.filter {
            if case .globalMaxReached = $0.status { return true }
            return false
        }.count
        self.noPendingTasks = results.filter {
            if case .noPendingTasks = $0.status { return true }
            return false
        }.count
        self.notTriggered = results.reduce(0) { $0 + $1.status.notTriggeredCount }
        self.triggered = results.reduce(0) { $0 + $1.status.successfulTriggers }
    }
}
