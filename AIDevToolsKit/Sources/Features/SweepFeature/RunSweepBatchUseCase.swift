import AIOutputSDK
import CLISDK
import ClaudeChainService
import Foundation
import GitHubService
import GitSDK
import Logging
import PipelineSDK
import PipelineService
import PRRadarCLIService
import PRRadarModelsService
import UseCaseSDK

public struct RunSweepBatchUseCase: UseCase {

    public struct Options: Sendable {
        public let baseBranch: String
        public let dryRun: Bool
        public let repoPath: URL
        public let taskDirectory: URL
        public let taskName: String

        public init(
            taskDirectory: URL,
            repoPath: URL,
            baseBranch: String = "main",
            dryRun: Bool = false
        ) {
            self.baseBranch = baseBranch
            self.dryRun = dryRun
            self.repoPath = repoPath
            self.taskDirectory = taskDirectory
            self.taskName = taskDirectory.lastPathComponent
        }
    }

    public struct Result: Sendable {
        public let batchBranch: String?
        public let message: String
        public let prURL: String?
        public let success: Bool
        public let sweepResult: SweepBatchStats

        public init(
            success: Bool,
            message: String,
            sweepResult: SweepBatchStats,
            batchBranch: String? = nil,
            prURL: String? = nil
        ) {
            self.batchBranch = batchBranch
            self.message = message
            self.prURL = prURL
            self.success = success
            self.sweepResult = sweepResult
        }
    }

    public enum Progress: Sendable {
        case checkingOpenPRs
        case completed(SweepBatchStats)
        case contentBlocks([AIContentBlock])
        case creatingBranch(String)
        case creatingPR
        case prCreated(prURL: String)
        case runningTasks
        case taskCompleted(String)
        case taskStarted(String)

        public var displayText: String {
            switch self {
            case .checkingOpenPRs:          return "Checking for open PRs..."
            case .contentBlocks:            return ""
            case .creatingBranch(let b):    return "Creating branch: \(b)"
            case .runningTasks:             return "Running sweep tasks..."
            case .taskStarted(let id):      return "Processing: \(id)"
            case .taskCompleted(let id):    return "Completed: \(id)"
            case .creatingPR:               return "Creating PR..."
            case .prCreated(let url):       return "PR created: \(url)"
            case .completed:                return "Completed"
            }
        }

        public var phaseId: String? {
            switch self {
            case .checkingOpenPRs, .creatingBranch:             return "prepare"
            case .contentBlocks, .runningTasks, .taskStarted, .taskCompleted: return "ai"
            case .creatingPR, .prCreated:                       return "finalize"
            case .completed:                                     return nil
            }
        }
    }

    public static let phases: [ChainExecutionPhase] = [
        ChainExecutionPhase(id: "prepare", displayName: "Prepare"),
        ChainExecutionPhase(id: "ai", displayName: "AI Execution"),
        ChainExecutionPhase(id: "finalize", displayName: "Create PR"),
    ]

    private let client: any AIClient
    private let git: GitClient
    private let logger = Logger(label: "RunSweepBatchUseCase")

    public init(client: any AIClient, git: GitClient = GitClient()) {
        self.client = client
        self.git = git
    }

    public func run(
        options: Options,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> Result {
        let repoDir = options.repoPath.path
        let taskName = options.taskName
        let branchPrefix = "claude-chain-\(taskName)-"

        let source = SweepClaudeChainSource(
            taskName: taskName,
            taskDirectory: options.taskDirectory,
            repoPath: options.repoPath,
            git: git
        )

        if options.dryRun {
            return try await runDryRun(source: source, options: options, onProgress: onProgress)
        }

        // Check for open sweep PRs before starting
        onProgress?(.checkingOpenPRs)
        let openCount = try await countOpenSweepPRs(branchPrefix: branchPrefix, repoDir: repoDir)
        if openCount > 0 {
            throw RunSweepBatchError.openPRExists(count: openCount, branchPrefix: branchPrefix)
        }

        // Create batch branch from base
        let batchBranch = makeBatchBranch(prefix: branchPrefix)
        onProgress?(.creatingBranch(batchBranch))
        logger.info("[\(taskName)] Creating batch branch: \(batchBranch)")

        // Swallowing intentionally: a fetch failure (network, shallow clone) is non-fatal — proceed with local state.
        if (try? await git.fetch(remote: "origin", branch: options.baseBranch, workingDirectory: repoDir)) != nil {
            try await git.checkout(ref: "FETCH_HEAD", workingDirectory: repoDir)
        }
        try await git.checkout(ref: batchBranch, forceCreate: true, workingDirectory: repoDir)

        // Phase A: Drain all tasks via pipeline
        onProgress?(.runningTasks)
        let taskSourceNode = TaskSourceNode(
            id: "sweep-source",
            displayName: "Sweep: \(taskName)",
            source: source
        )
        let taskConfiguration = PipelineConfiguration(
            executionMode: .all,
            provider: client,
            workingDirectory: repoDir
        )
        let runner = PipelineRunner()
        _ = try await runner.run(
            nodes: [taskSourceNode],
            configuration: taskConfiguration
        ) { event in
            switch event {
            case .nodeStarted(let id, _) where id != "sweep-source":
                onProgress?(.taskStarted(id))
            case .nodeCompleted(let id, _) where id != "sweep-source":
                onProgress?(.taskCompleted(id))
            case .nodeProgress(_, let progress):
                if case .contentBlocks(let blocks) = progress {
                    onProgress?(.contentBlocks(blocks))
                }
            default:
                break
            }
        }

        let sweepResult = await source.batchStats()

        // Phase B: Create PR if any tasks produced changes
        var prURL: String?
        if sweepResult.modifyingTasks > 0 {
            onProgress?(.creatingPR)
            logger.info("[\(taskName)] \(sweepResult.modifyingTasks) modifying task(s), creating PR")

            let batchDescription = "Sweep: \(sweepResult.modifyingTasks) file(s) updated, \(BranchInfo.sweepCursorPrefix)\(sweepResult.finalCursor ?? "end")"
            let prConfig = PRConfiguration(labels: [Constants.defaultPRLabel])
            let commentStep = ChainPRCommentStep(
                id: "pr-comment-step",
                displayName: "Post PR Comment",
                baseBranch: options.baseBranch,
                client: client,
                gitClient: git,
                projectName: taskName,
                taskDescription: batchDescription,
                dryRun: options.dryRun
            )
            let prConfiguration = PipelineConfiguration(
                executionMode: .all,
                provider: client,
                workingDirectory: repoDir
            )
            var prNodes: [any PipelineNode] = []
            let templatePath = options.taskDirectory.appendingPathComponent("pr-template.md").path
            let prStep = PRStep(
                id: "pr-step",
                displayName: "Create PR",
                baseBranch: options.baseBranch,
                configuration: prConfig,
                gitClient: git,
                projectName: taskName,
                taskDescription: batchDescription,
                prTemplatePath: FileManager.default.fileExists(atPath: templatePath) ? templatePath : nil
            )
            prNodes.append(prStep)
            prNodes.append(commentStep)
            let prContext = try await runner.run(
                nodes: prNodes,
                configuration: prConfiguration
            ) { _ in }
            prURL = prContext[PRStep.prURLKey]
            if let url = prURL {
                onProgress?(.prCreated(prURL: url))
            }
        }

        onProgress?(.completed(sweepResult))

        let message = sweepResult.tasks == 0 && sweepResult.skipped == 0
            ? "No files to process"
            : "\(sweepResult.tasks) task(s) run, \(sweepResult.modifyingTasks) modifying, \(sweepResult.skipped) skipped, cursor at \(sweepResult.finalCursor ?? "end")"

        return Result(
            success: true,
            message: message,
            sweepResult: sweepResult,
            batchBranch: batchBranch,
            prURL: prURL
        )
    }

    // MARK: - Private

    private func runDryRun(
        source: SweepClaudeChainSource,
        options: Options,
        onProgress: (@Sendable (Progress) -> Void)?
    ) async throws -> Result {
        onProgress?(.runningTasks)
        let sweepResult = try await source.dryRunStats()
        onProgress?(.completed(sweepResult))
        let message = sweepResult.tasks == 0 && sweepResult.skipped == 0
            ? "No files to process"
            : "\(sweepResult.tasks) task(s), \(sweepResult.modifyingTasks) modifying, \(sweepResult.skipped) skipped"
        return Result(success: true, message: message, sweepResult: sweepResult)
    }

    private func makeBatchBranch(prefix: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return prefix + formatter.string(from: Date())
    }

    private func countOpenSweepPRs(branchPrefix: String, repoDir: String) async throws -> Int {
        let repoSlug = try await detectRepoSlug(workingDirectory: repoDir)
        let service = try resolveGitHubService(repoSlug: repoSlug)
        let openPRs = try await service.listPullRequests(limit: 100, filter: PRFilter(state: .open))
        return openPRs.filter { ($0.headRefName ?? "").hasPrefix(branchPrefix) }.count
    }

    private func detectRepoSlug(workingDirectory: String) async throws -> String {
        if let repo = ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"], !repo.isEmpty {
            return repo
        }
        let remoteURL = try await git.remoteGetURL(workingDirectory: workingDirectory)
        return remoteURL
            .replacingOccurrences(of: "git@github.com:", with: "")
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveGitHubService(repoSlug: String) throws -> any GitHubPRServiceProtocol {
        let env = ProcessInfo.processInfo.environment
        guard let token = env["GH_TOKEN"] ?? env["GITHUB_TOKEN"] else {
            throw RunSweepBatchError.openPRQueryFailed(branchPrefix: "")
        }
        let parts = repoSlug.split(separator: "/")
        guard parts.count == 2 else {
            throw RunSweepBatchError.openPRQueryFailed(branchPrefix: "")
        }
        return GitHubServiceFactory.make(token: token, owner: String(parts[0]), repo: String(parts[1]))
    }
}

