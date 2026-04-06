import AIOutputSDK
import AnthropicSDK
import ArgumentParser
import ClaudeChainFeature
import ClaudeChainSDK
import ClaudeChainService
import ClaudeCLISDK
import CodexCLISDK
import CredentialService
import Foundation
import GitSDK
import ProviderRegistryService

struct FinalizeStagedCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "finalize-staged",
        abstract: "Create a PR from a branch staged by run-task --staging-only"
    )

    @Option(help: "Project name within claude-chain/ directory")
    var project: String

    @Option(help: "Branch name to push and create a PR from")
    var branchName: String

    @Option(help: "Task description (must match the staged task exactly)")
    var taskDescription: String

    @Option(help: "Base branch for the PR (overrides configuration.yml)")
    var baseBranch: String?

    @Option(help: "Path to the repository root (defaults to current directory)")
    var repoPath: String?

    @Option(help: "AI provider name to override the default")
    var provider: String?

    @Option(help: "Credential account name to override auto-detection")
    var githubAccount: String?

    @Flag(help: "Generate and print the PR comment without pushing, creating a PR, or posting")
    var dryRun: Bool = false

    public init() {}

    func run() async throws {
        let repoURL: URL
        if let repoPath {
            repoURL = URL(fileURLWithPath: (repoPath as NSString).standardizingPath)
        } else {
            repoURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }

        let (gitEnvironment, resolver) = resolveGitHubCredentials(githubAccount: githubAccount)
        let registry = makeProviderRegistry(credentialResolver: resolver)
        guard let client = provider.flatMap({ registry.client(named: $0) }) ?? registry.defaultClient else {
            print("Error: No AI provider available. Configure an API key or install Claude CLI.")
            throw ExitCode.failure
        }

        let resolvedBaseBranch: String
        if let baseBranch {
            resolvedBaseBranch = baseBranch
        } else {
            let chainDir = repoURL.appendingPathComponent("claude-chain").path
            let chainProject = Project(
                name: project,
                basePath: (chainDir as NSString).appendingPathComponent(project)
            )
            let repository = ProjectRepository(repo: "")
            // Swallowing intentionally: missing/invalid config falls back to defaults so the task can still run.
        let config = (try? repository.loadLocalConfiguration(project: chainProject))
                ?? ProjectConfiguration.default(project: chainProject)
            resolvedBaseBranch = config.getBaseBranch(defaultBaseBranch: Constants.defaultBaseBranch)
        }

        print("=== Finalize Staged Task\(dryRun ? " (DRY RUN)" : "") ===")
        print("Project: \(project)")
        print("Branch: \(branchName)")
        print("Task: \(taskDescription)")
        print("Provider: \(client.name)")
        print()

        let useCase = FinalizeStagedTaskUseCase(client: client, git: GitClient(environment: gitEnvironment))
        let result = try await useCase.run(
            options: .init(
                repoPath: repoURL,
                projectName: project,
                baseBranch: resolvedBaseBranch,
                branchName: branchName,
                taskDescription: taskDescription,
                dryRun: dryRun
            )
        ) { progress in
            Self.handleProgress(progress, dryRun: dryRun)
        }

        print()
        if result.success {
            print(dryRun ? "=== Dry Run Complete ===" : "=== PR Created ===")
            print(result.message)
            if let prURL = result.prURL {
                print("PR: \(prURL)")
            }
            if dryRun {
                print("Check logs for full PR comment: swift run ai-dev-tools-kit --log-level debug logs")
            }
        } else {
            print("=== Failed ===")
            print(result.message)
            throw ExitCode.failure
        }
    }

    private static func handleProgress(_ progress: RunSpecChainTaskUseCase.Progress, dryRun: Bool = false) {
        switch progress {
        case .finalizing:
            print("=== Phase: Finalizing ===")
            print("Marking task complete, pushing branch, creating PR...")
        case .prCreated(let prNumber, let prURL):
            print("PR #\(prNumber) created: \(prURL)")
        case .generatingSummary:
            print("\n=== Phase: PR Summary ===")
            print("Generating PR summary...")
        case .summaryStreamEvent:
            break
        case .summaryCompleted(let summary):
            if dryRun {
                print("\n=== PR Comment Preview ===")
                print(summary)
                print("=== End PR Comment Preview ===")
            } else {
                print("Summary generated (\(summary.count) chars)")
            }
        case .postingPRComment:
            print("\n=== Phase: Post PR Comment ===")
        case .prCommentPosted:
            print("PR comment posted.")
        case .completed(let prURL):
            if let prURL {
                print("\n=== Completed === PR: \(prURL)")
            } else {
                print("\n=== Completed ===")
            }
        case .failed(let phase, let error):
            print("\nFailed during \(phase): \(error)")
        default:
            break
        }
    }

}
