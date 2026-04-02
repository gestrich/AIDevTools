import ArgumentParser
import DataPathsService
import Foundation
import MarkdownPlannerFeature
import PipelineSDK
import ProviderRegistryService
import RepositorySDK
import SettingsService

struct MarkdownPlannerPlanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan",
        abstract: "Generate an implementation plan from a prompt"
    )

    @Argument(help: "Text describing the task")
    var text: String

    @Flag(help: "Execute the plan immediately after generating it")
    var execute = false

    @Option(help: "Provider to use (default: first registered)")
    var provider: String?

    @Option(help: "Data directory path (overrides app settings)")
    var dataPath: String?

    func run() async throws {
        let settings = try ReposCommand.makeSettingsService(dataPath: dataPath)
        let repos = try settings.repositoryStore.loadAll()

        let registry = makeProviderRegistry()
        let client = provider.flatMap { registry.client(named: $0) } ?? registry.defaultClient!

        let service = MarkdownPlannerService(
            client: client,
            resolveProposedDirectory: { repo in
                (repo.planner ?? MarkdownPlannerRepoSettings()).resolvedProposedDirectory(repoPath: repo.path)
            }
        )
        let result = try await service.generate(
            options: MarkdownPlannerService.GenerateOptions(
                prompt: text,
                repositories: repos
            )
        ) { progress in
            Self.printProgress(progress)
        }

        if execute {
            printColored("\nStarting execution...", color: .cyan)
            let planPath = result.planURL.path(percentEncoded: false)
            let executeRepository = repos.first { planPath.hasPrefix($0.path.path(percentEncoded: false)) }
            let executeService = MarkdownPlannerService(
                client: client,
                resolveProposedDirectory: { repo in
                    (repo.planner ?? MarkdownPlannerRepoSettings()).resolvedProposedDirectory(repoPath: repo.path)
                }
            )
            let timer = TimerDisplay(maxRuntimeSeconds: 90 * 60, scriptStartTime: Date())
            let blueprint = try await executeService.buildExecutePipeline(
                options: MarkdownPlannerService.ExecuteOptions(
                    executeMode: .all,
                    planPath: result.planURL,
                    repoPath: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                    repository: executeRepository
                )
            )
            let state = PipelineCLIState(totalPhases: blueprint.initialNodeManifest.count)
            _ = try await PipelineRunner().run(
                nodes: blueprint.nodes,
                configuration: blueprint.configuration,
                onProgress: { [timer, state] event in
                    MarkdownPlannerExecuteCommand.handlePipelineEvent(event, timer: timer, state: state)
                }
            )
            timer.stop()
            if state.phasesExecuted > 0 {
                printColored("\u{2713} All steps completed!", color: .green)
            }
        }
    }

    private static func printProgress(_ progress: MarkdownPlannerService.GenerateProgress) {
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
