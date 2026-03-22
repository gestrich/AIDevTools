import ArgumentParser
import EvalFeature
import EvalService
import Foundation
import RepositorySDK

struct ListCasesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-cases",
        abstract: "List eval cases and their definitions"
    )

    @Option(help: "Path to cases directory")
    var casesDir: String?

    @Option(help: "Repository path to resolve cases directory from stored config")
    var repo: String?

    @Option(help: "Data directory path (default: ~/Desktop/ai-dev-tools)")
    var dataPath: String?

    @Option var caseId: String?
    @Option(help: "Filter by skill name (show cases referencing this skill)")
    var skill: String?
    @Option var suite: String?

    func validate() throws {
        if casesDir != nil && repo != nil {
            throw ValidationError("Cannot specify both --cases-dir and --repo")
        }
        if casesDir == nil && repo == nil {
            throw ValidationError("Must specify either --cases-dir or --repo")
        }
    }

    func run() throws {
        let resolvedCasesDir: URL

        if let casesDir {
            resolvedCasesDir = URL(fileURLWithPath: casesDir)
        } else if let repo {
            let repoURL = URL(fileURLWithPath: repo, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            let repoStore = RepositoryStore.fromCLI(dataPath: dataPath)
            let repoConfig = try repoStore.repoConfig(forRepoAt: repoURL)
            let evalSettingsStore = EvalRepoSettingsStore.fromCLI(dataPath: dataPath)
            resolvedCasesDir = try evalSettingsStore.casesDirectory(forRepo: repoConfig)
        } else {
            throw ValidationError("Must specify either --cases-dir or --repo")
        }

        let cases = try ListEvalCasesUseCase().run(
            ListEvalCasesUseCase.Options(
                casesDirectory: resolvedCasesDir,
                caseId: caseId,
                skill: skill,
                suite: suite
            )
        )

        if cases.isEmpty {
            print("No eval cases found matching filters.")
            return
        }

        for evalCase in cases {
            print(evalCase.summaryDescription)
            print()
        }

        print("\(cases.count) case(s) found.")
    }
}
