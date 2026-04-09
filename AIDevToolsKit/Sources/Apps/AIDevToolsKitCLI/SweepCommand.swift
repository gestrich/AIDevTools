import AIOutputSDK
import ArgumentParser
import ClaudeChainService
import CredentialFeature
import Foundation
import GitSDK
import ProviderRegistryService
import SweepFeature

struct SweepCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sweep",
        abstract: "Sweep-mode chain operations — run AI tasks over files in a codebase",
        subcommands: [SweepRunCommand.self]
    )

    init() {}
}

struct SweepRunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a sweep batch: iterate AI tasks over files matching the configured pattern"
    )

    @Option(help: "Path to the sweep task directory (containing config.yaml, spec.md, state.json)")
    var task: String

    @Option(help: "Path to the repository root (defaults to current directory)")
    var repo: String?

    @Option(help: "Base branch for PR creation")
    var baseBranch: String = "main"

    @Option(help: "AI provider name to override the default")
    var provider: String?

    @Option(help: "Credential account name for GitHub auth")
    var githubAccount: String?

    @Option(help: "GitHub token (overrides all other credential sources)")
    var githubToken: String?

    @Flag(help: "Print the PR comment without posting it")
    var dryRun: Bool = false

    init() {}

    func run() async throws {
        let taskURL = URL(fileURLWithPath: (task as NSString).standardizingPath)
        let repoURL: URL
        if let repo {
            repoURL = URL(fileURLWithPath: (repo as NSString).standardizingPath)
        } else {
            repoURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }

        let resolver = resolveGitHubCredentials(githubAccount: githubAccount, githubToken: githubToken)
        let registry = makeProviderRegistry(credentialResolver: resolver)
        guard let client = provider.flatMap({ registry.client(named: $0) }) ?? registry.defaultClient else {
            print("Error: No AI provider available. Configure an API key or install Claude CLI.")
            throw ExitCode.failure
        }

        let taskName = taskURL.lastPathComponent
        print("=== Sweep Run ===")
        print("Task:     \(taskName)")
        print("Repo:     \(repoURL.path)")
        print("Provider: \(client.name)")
        print()

        let useCase = RunSweepBatchUseCase(client: client, git: GitClient(printOutput: false, environment: resolver.gitEnvironment))
        let options = RunSweepBatchUseCase.Options(
            taskDirectory: taskURL,
            taskRelativePath: taskURL.path.hasPrefix(repoURL.path + "/")
                ? String(taskURL.path.dropFirst(repoURL.path.count + 1))
                : taskURL.lastPathComponent,
            repoPath: repoURL,
            baseBranch: baseBranch,
            dryRun: dryRun
        )

        let result = try await useCase.run(options: options) { progress in
            Self.handleProgress(progress)
        }

        print()
        if result.success {
            print("=== Sweep Complete ===")
            print(result.message)
            if let prURL = result.prURL {
                print("PR: \(prURL)")
            }
        } else {
            print("=== Sweep Failed ===")
            print(result.message)
            throw ExitCode.failure
        }
    }

    private static func handleProgress(_ progress: RunSweepBatchUseCase.Progress) {
        switch progress {
        case .checkingOpenPRs:
            print("Checking for open sweep PRs...")
        case .creatingBranch(let branch):
            print("Creating batch branch: \(branch)")
        case .creatingWorktree(let path):
            print("Creating worktree: \(URL(fileURLWithPath: path).lastPathComponent)")
        case .runningTasks:
            print("Running sweep tasks...")
        case .taskStarted(let id):
            print("  → \(id)")
        case .taskCompleted(let id):
            print("  ✓ \(id)")
        case .creatingPR:
            print("Creating PR for batch changes...")
        case .prCreated(let url):
            print("PR: \(url)")
        case .contentBlocks:
            break
        case .completed(let r):
            print("\(r.tasks) task(s), \(r.modifyingTasks) modifying, \(r.skipped) skipped")
        }
    }

}
