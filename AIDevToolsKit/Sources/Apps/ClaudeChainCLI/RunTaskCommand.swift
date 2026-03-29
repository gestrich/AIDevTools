import AIOutputSDK
import AnthropicSDK
import ArgumentParser
import ClaudeChainFeature
import ClaudeCLISDK
import CodexCLISDK
import CredentialService
import Foundation
import GitSDK
import ProviderRegistryService

struct RunTaskCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run-task",
        abstract: "Execute a chain task end-to-end: prepare, run AI, finalize, create PR"
    )

    @Option(help: "Project name within claude-chain/ directory")
    var project: String

    @Option(help: "Path to the repository root (defaults to current directory)")
    var repoPath: String?

    @Option(help: "AI provider name to override the default")
    var provider: String?

    @Option(help: "Credential account name to override auto-detection")
    var githubAccount: String?

    public init() {}

    func run() async throws {
        let repoURL: URL
        if let repoPath {
            repoURL = URL(fileURLWithPath: (repoPath as NSString).standardizingPath)
        } else {
            repoURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }

        // Resolve GitHub auth
        let service = CredentialSettingsService()
        let account = githubAccount ?? (try? service.listCredentialAccounts())?.first ?? "default"
        let resolver = CredentialResolver(settingsService: service, githubAccount: account)

        var gitEnvironment: [String: String]?
        if case .token(let token) = resolver.getGitHubAuth() {
            setenv("GH_TOKEN", token, 1)
            gitEnvironment = ["GH_TOKEN": token]
        }

        // Build provider registry and resolve AI client
        let registry = makeRegistry(credentialResolver: resolver)
        guard let client = provider.flatMap({ registry.client(named: $0) }) ?? registry.defaultClient else {
            print("Error: No AI provider available. Configure an API key or install Claude CLI.")
            throw ExitCode.failure
        }

        print("=== Run Task ===")
        print("Project: \(project)")
        print("Repo: \(repoURL.path)")
        print("Provider: \(client.name)")
        print()

        let git = GitClient(environment: gitEnvironment)
        let useCase = RunChainTaskUseCase(client: client, git: git)
        let options = RunChainTaskUseCase.Options(
            repoPath: repoURL,
            projectName: project
        )

        let result = try await useCase.run(options: options) { progress in
            Self.handleProgress(progress)
        }

        print()
        if result.success {
            print("=== Task Completed ===")
            print(result.message)
            if let prURL = result.prURL {
                print("PR: \(prURL)")
            }
            print("Phases completed: \(result.phasesCompleted)")
        } else {
            print("=== Task Failed ===")
            print(result.message)
            throw ExitCode.failure
        }
    }

    private static func handleProgress(_ progress: RunChainTaskUseCase.Progress) {
        switch progress {
        case .preparingProject:
            print("=== Phase: Preparing ===")

        case .preparedTask(let description, let index, let total):
            print("Task \(index)/\(total): \(description)")

        case .runningPreScript:
            print("\n=== Phase: Pre-Action Script ===")

        case .preScriptCompleted(let result):
            if !result.scriptExists {
                print("Pre-action script: skipped (not found)")
            } else {
                print("Pre-action script: \(result.success ? "completed" : "failed")")
                if !result.stdout.isEmpty {
                    print(result.stdout)
                }
            }

        case .runningAI(let taskDescription):
            print("\n=== Phase: AI Execution ===")
            print("Task: \(taskDescription)")

        case .aiStreamEvent:
            break

        case .aiOutput(let text):
            print(text, terminator: "")

        case .aiCompleted:
            print("\nAI execution completed.")

        case .runningPostScript:
            print("\n=== Phase: Post-Action Script ===")

        case .postScriptCompleted(let result):
            if !result.scriptExists {
                print("Post-action script: skipped (not found)")
            } else {
                print("Post-action script: \(result.success ? "completed" : "failed")")
                if !result.stdout.isEmpty {
                    print(result.stdout)
                }
            }

        case .finalizing:
            print("\n=== Phase: Finalizing ===")
            print("Committing changes, pushing branch, creating PR...")

        case .prCreated(let prNumber, let prURL):
            print("PR #\(prNumber) created: \(prURL)")

        case .generatingSummary:
            print("\n=== Phase: PR Summary ===")
            print("Generating PR summary...")

        case .summaryStreamEvent:
            break

        case .summaryCompleted(let summary):
            print("Summary generated (\(summary.count) chars)")

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
        }
    }

    private func makeRegistry(credentialResolver: CredentialResolver) -> ProviderRegistry {
        var providers: [any AIClient] = [
            ClaudeProvider(),
            CodexProvider(),
        ]
        if let key = credentialResolver.getAnthropicKey(), !key.isEmpty {
            providers.append(AnthropicProvider(apiClient: AnthropicAPIClient(apiKey: key)))
        }
        return ProviderRegistry(providers: providers)
    }
}
