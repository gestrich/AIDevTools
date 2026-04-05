import AIOutputSDK
import CLISDK
import ClaudeChainFeature
import ClaudeChainService
import Foundation
import GitSDK
import Logging
import PipelineSDK
import PipelineService
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
        case creatingBranch(String)
        case creatingPR
        case prCreated(prURL: String)
        case runningTasks
        case taskCompleted(String)
        case taskStarted(String)
    }

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
            default:
                break
            }
        }

        let sweepResult = await source.batchStats()

        // Phase B: Create PR if any tasks produced changes
        var prURL: String? = nil
        if sweepResult.modifyingTasks > 0 {
            onProgress?(.creatingPR)
            logger.info("[\(taskName)] \(sweepResult.modifyingTasks) modifying task(s), creating PR")

            let batchDescription = "Sweep [\(taskName)]: \(sweepResult.modifyingTasks) file(s) updated, cursor at \(sweepResult.finalCursor ?? "end")"
            let prConfig = PRConfiguration(labels: [Constants.defaultPRLabel])
            let prStep = PRStep(
                id: "pr-step",
                displayName: "Create PR",
                baseBranch: options.baseBranch,
                configuration: prConfig,
                gitClient: git,
                projectName: taskName,
                taskDescription: batchDescription
            )
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
            let prContext = try await runner.run(
                nodes: [prStep, commentStep],
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

    private func makeBatchBranch(prefix: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return prefix + formatter.string(from: Date())
    }

    private func countOpenSweepPRs(branchPrefix: String, repoDir: String) async throws -> Int {
        let cliClient = CLIClient()
        let result = try await cliClient.execute(
            command: "gh",
            arguments: ["pr", "list", "--state", "open", "--json", "headRefName"],
            workingDirectory: repoDir,
            environment: nil,
            printCommand: false
        )
        guard result.isSuccess, let data = result.stdout.data(using: .utf8) else { return 0 }
        let prs = try JSONDecoder().decode([OpenPR].self, from: data)
        return prs.filter { $0.headRefName.hasPrefix(branchPrefix) }.count
    }
}

private struct OpenPR: Decodable {
    let headRefName: String
}

public enum RunSweepBatchError: LocalizedError {
    case openPRExists(count: Int, branchPrefix: String)

    public var errorDescription: String? {
        switch self {
        case .openPRExists(let count, let prefix):
            return "\(count) open PR(s) already exist with prefix '\(prefix)'. Merge or close them before starting a new batch."
        }
    }
}
