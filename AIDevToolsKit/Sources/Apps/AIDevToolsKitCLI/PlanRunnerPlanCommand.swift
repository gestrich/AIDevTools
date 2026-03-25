import ArgumentParser
import DataPathsService
import Foundation
import PlanRunnerFeature
import PlanRunnerService
import RepositorySDK

struct PlanRunnerPlanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan",
        abstract: "Generate an implementation plan from a prompt"
    )

    @Argument(help: "Text describing the task")
    var text: String

    @Flag(help: "Execute the plan immediately after generating it")
    var execute = false

    @Option(help: "Data directory path (overrides app settings)")
    var dataPath: String?

    func run() async throws {
        let service = try DataPathsService.fromCLI(dataPath: dataPath)
        let store = try ReposCommand.makeStore(service)
        let repos = try store.loadAll()
        let planSettings = try ReposCommand.makePlanSettingsStore(service)

        let useCase = GeneratePlanUseCase(
            resolveProposedDirectory: { repo in
                try planSettings.resolvedProposedDirectory(forRepo: repo)
            }
        )
        let result = try await useCase.run(
            GeneratePlanUseCase.Options(
                prompt: text,
                repositories: repos
            )
        ) { progress in
            Self.printProgress(progress)
        }

        if execute {
            printColored("\nStarting execution...", color: .cyan)
            let executeCmd = try PlanRunnerExecuteCommand.parse(["--plan", result.planURL.path])
            try await executeCmd.run()
        }
    }

    private static func printProgress(_ progress: GeneratePlanUseCase.Progress) {
        switch progress {
        case .matchingRepo:
            printColored("Step 1/3: Matching repository...", color: .cyan)
        case .matchedRepo(let repoId, let interpretedRequest):
            printColored("Matched repository: \(repoId)", color: .green)
            printColored("Interpreted request: \(interpretedRequest)", color: .green)
        case .generatingPlan:
            printColored("Step 2/3: Generating implementation plan...", color: .cyan)
        case .generatedPlan(let filename):
            printColored("Generated plan: \(filename)", color: .green)
        case .writingPlan:
            printColored("Step 3/3: Writing plan to disk...", color: .cyan)
        case .completed(let planURL, _):
            printColored("Plan written to: \(planURL.path)", color: .green)
        }
    }
}
