import AIOutputSDK
import ArgumentParser
import DataPathsService
import EvalFeature
import EvalService
import Foundation
import ProviderRegistryService
import RepositorySDK
import SettingsService

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

    @Option(help: "Provider name")
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
            let settings = try ReposCommand.makeSettingsService(dataPath: dataPath)
            let repoConfig = try settings.repositoryStore.repoConfig(forRepoAt: repoURL)
            resolvedOutputDir = try service.path(for: .evalsOutput(repoConfig.name))
        } else {
            throw ValidationError("Must specify either --output-dir or --repo")
        }

        let root = try CLICompositionRoot.create()
        let registry = root.evalProviderRegistry
        let resolvedProvider = Provider(rawValue: provider)
        let entry = registry.entries.first(where: { $0.name == provider })
        guard let defaultEntry = registry.defaultEntry else {
            throw ValidationError("No eval providers configured")
        }
        let formatter = entry?.client.streamFormatter ?? defaultEntry.client.streamFormatter
        let rubricFormatter = entry?.client.streamFormatter ?? defaultEntry.client.streamFormatter
        let options = ReadCaseOutputUseCase.Options(
            caseId: caseId,
            formatter: formatter,
            provider: resolvedProvider,
            outputDirectory: resolvedOutputDir,
            rubricFormatter: rubricFormatter
        )

        let output = try ReadCaseOutputUseCase().run(options)
        print(output.mainOutput)

        if let rubricOutput = output.rubricOutput {
            print("\n--- Rubric Evaluation ---\n")
            print(rubricOutput)
        }
    }
}
