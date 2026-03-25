import ArgumentParser
import DataPathsService
import EvalFeature
import Foundation
import RepositorySDK

struct ClearArtifactsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear-artifacts",
        abstract: "Delete all prior eval run artifacts"
    )

    @Option(help: "Path to output directory")
    var outputDir: String?

    @Option(help: "Repository path to resolve output directory from stored config")
    var repo: String?

    @Option(help: "Data directory path (overrides app settings)")
    var dataPath: String?

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

        try ClearArtifactsUseCase().run(outputDirectory: resolvedOutputDir)
        print("Cleared artifacts in \(resolvedOutputDir.path)")
    }
}
