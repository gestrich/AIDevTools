import ArgumentParser
import EvalFeature
import EvalService
import Foundation
import RepositorySDK

struct RunEvalsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run-evals",
        abstract: "Run evaluation cases against AI providers"
    )

    @Option(help: "Path to cases directory")
    var casesDir: String?

    @Option(help: "Path to output directory (artifacts, schemas)")
    var outputDir: String?

    @Option(help: "Repository path to resolve directories from stored config")
    var repo: String?

    @Option(help: "Data directory path (default: ~/Desktop/ai-dev-tools)")
    var dataPath: String?

    @Option var caseId: String?
    @Option var suite: String?
    @Option var model: String?
    @Flag var keepTraces = false
    @Flag(help: "Print debug info (e.g. exact CLI arguments passed to providers)")
    var debug = false
    @Option var provider: ProviderChoice = .codex
    @Option var resultSchema: String?
    @Option var rubricSchema: String?

    func validate() throws {
        if casesDir != nil && repo != nil {
            throw ValidationError("Cannot specify both --cases-dir and --repo")
        }
        if casesDir == nil && repo == nil {
            throw ValidationError("Must specify either --cases-dir or --repo")
        }
    }

    func run() async throws {
        let resolvedCasesDir: URL
        let resolvedOutputDir: URL
        let resolvedRepoRoot: URL

        if let casesDir {
            resolvedCasesDir = URL(fileURLWithPath: casesDir)
            resolvedRepoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            if let outputDir {
                resolvedOutputDir = URL(fileURLWithPath: outputDir)
            } else {
                let store = RepositoryStore.fromCLI(dataPath: dataPath)
                resolvedOutputDir = store.dataPath
            }
        } else if let repo {
            let repoURL = URL(fileURLWithPath: repo, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            let repoStore = RepositoryStore.fromCLI(dataPath: dataPath)
            let repoConfig = try repoStore.repoConfig(forRepoAt: repoURL)
            let evalSettingsStore = EvalRepoSettingsStore.fromCLI(dataPath: dataPath)
            resolvedCasesDir = try evalSettingsStore.casesDirectory(forRepo: repoConfig)
            resolvedOutputDir = try repoStore.outputDirectory(forRepoAt: repoURL)
            resolvedRepoRoot = repoURL
        } else {
            throw ValidationError("Must specify either --cases-dir or --repo")
        }

        let summaries = try await RunEvalsUseCase().run(
            RunEvalsUseCase.Options(
                casesDirectory: resolvedCasesDir,
                outputDirectory: resolvedOutputDir,
                caseId: caseId,
                suite: suite,
                providers: provider.resolved,
                resultSchemaPath: resultSchema.map { URL(fileURLWithPath: $0) },
                rubricSchemaPath: rubricSchema.map { URL(fileURLWithPath: $0) },
                model: model,
                keepTraces: keepTraces,
                debug: debug,
                repoRoot: resolvedRepoRoot
            )
        ) { progress in
            Self.printProgress(progress)
        }

        if summaries.isEmpty {
            print("No eval cases found matching filters.")
        }

        let totalFailures = summaries.reduce(0) { $0 + $1.failed }
        if totalFailures > 0 {
            throw ExitCode.failure
        }
    }
}

extension RunEvalsCommand {
    static func printProgress(_ progress: RunEvalsUseCase.Progress) {
        switch progress {
        case .startingProvider(let provider, let caseCount):
            print("\n[\(provider)] Running \(caseCount) eval\(caseCount == 1 ? "" : "s")...")

        case .startingCase(let caseId, let index, let total, let provider, _):
            print("[\(provider)] (\(index + 1)/\(total)) Running \(caseId)...")

        case .caseOutput(_, let text):
            print(text, terminator: "")

        case .completedCase(let result, _, _, _):
            if result.passed {
                if !result.skipped.isEmpty {
                    print("  PASS (skip): \(result.caseId)")
                } else {
                    print("  PASS: \(result.caseId)")
                }
            } else {
                print("  FAIL: \(result.caseId)")
                for error in result.errors {
                    print("    \(error)")
                }
            }
            for check in result.skillChecks {
                print("    skill: \(check.displayDescription)")
            }
            for skip in result.skipped {
                print("    skip: \(skip)")
            }

        case .completedProvider(let summary):
            print("\n[\(summary.provider)] Done: \(summary.passed) passed, \(summary.failed) failed, \(summary.skipped) skipped / \(summary.total) total")
        }
    }
}

enum ProviderChoice: String, ExpressibleByArgument, Sendable, Decodable {
    case codex
    case claude
    case both

    var resolved: [Provider] {
        switch self {
        case .codex: return [.codex]
        case .claude: return [.claude]
        case .both: return [.codex, .claude]
        }
    }
}
