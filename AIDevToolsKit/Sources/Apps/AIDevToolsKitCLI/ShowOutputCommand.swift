import AIOutputSDK
import ArgumentParser
import ClaudeCLISDK
import CodexCLISDK
import DataPathsService
import EvalFeature
import EvalSDK
import EvalService
import Foundation
import RepositorySDK

struct ShowOutputCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show-output",
        abstract: "Display formatted output from a completed eval run"
    )

    @Option(help: "Path to output directory")
    var outputDir: String?

    @Option(help: "Repository path to resolve output directory from stored config")
    var repo: String?

    @Option(help: "Data directory path (overrides app settings)")
    var dataPath: String?

    @Option(help: "The eval case ID (e.g. feature-flags.add-bool-flag-structured)")
    var caseId: String

    @Option(help: "Provider name (e.g. claude, codex)")
    var provider: String

    func validate() throws {
        if outputDir != nil && repo != nil {
            throw ValidationError("Cannot specify both --output-dir and --repo")
        }
        if outputDir == nil && repo == nil {
            throw ValidationError("Must specify either --output-dir or --repo")
        }
    }

    func run() throws {
        let resolvedOutputDir: URL

        if let outputDir {
            resolvedOutputDir = URL(fileURLWithPath: outputDir)
        } else if let repo {
            let repoURL = URL(fileURLWithPath: repo, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            let service = try DataPathsService.fromCLI(dataPath: dataPath)
            let store = try ReposCommand.makeStore(service)
            let repoConfig = try store.repoConfig(forRepoAt: repoURL)
            resolvedOutputDir = try service.path(for: .repoOutput(repoConfig.name))
        } else {
            throw ValidationError("Must specify either --output-dir or --repo")
        }

        let resolvedProvider = Provider(rawValue: provider)
        let options = ReadCaseOutputUseCase.Options(
            caseId: caseId,
            formatter: Self.formatter(for: resolvedProvider),
            provider: resolvedProvider,
            outputDirectory: resolvedOutputDir,
            rubricFormatter: ClaudeStreamFormatter()
        )

        let output = try ReadCaseOutputUseCase().run(options)
        print(output.mainOutput)

        if let rubricOutput = output.rubricOutput {
            print("\n--- Rubric Evaluation ---\n")
            print(rubricOutput)
        }
    }

    private static func formatter(for provider: Provider) -> any StreamFormatter {
        switch provider.rawValue {
        case "codex": CodexStreamFormatter()
        default: ClaudeStreamFormatter()
        }
    }
}
