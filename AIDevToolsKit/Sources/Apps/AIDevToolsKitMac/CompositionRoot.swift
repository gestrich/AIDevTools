import ClaudeCLISDK
import CodexCLISDK
import DataPathsService
import EvalService
import MarkdownPlannerService
import ProviderRegistryService
import RepositorySDK

@MainActor
struct CompositionRoot {
    let dataPathsService: DataPathsService
    let evalSettingsStore: EvalRepoSettingsStore
    let evalProviderRegistry: EvalProviderRegistry
    let planSettingsStore: MarkdownPlannerRepoSettingsStore
    let providerModel: ProviderModel
    let repositoryStore: RepositoryStore
    let settingsModel: SettingsModel

    static func create() throws -> CompositionRoot {
        let settingsModel = SettingsModel()
        let dataPathsService = try DataPathsService(rootPath: settingsModel.dataPath)
        try MigrateDataPathsUseCase(dataPathsService: dataPathsService).run()

        let repositoryStore = RepositoryStore(
            repositoriesFile: try dataPathsService.path(for: .repositories).appending(path: "repositories.json")
        )
        let evalSettingsStore = EvalRepoSettingsStore(
            filePath: try dataPathsService.path(for: .evalSettings).appending(path: "eval-settings.json")
        )
        let planSettingsStore = MarkdownPlannerRepoSettingsStore(
            filePath: try dataPathsService.path(for: .planSettings).appending(path: "plan-settings.json")
        )

        let evalProviderRegistry = EvalProviderRegistry(entries: [
            EvalProviderEntry(client: ClaudeProvider()),
            EvalProviderEntry(client: CodexProvider()),
        ])

        return CompositionRoot(
            dataPathsService: dataPathsService,
            evalSettingsStore: evalSettingsStore,
            evalProviderRegistry: evalProviderRegistry,
            planSettingsStore: planSettingsStore,
            providerModel: ProviderModel(),
            repositoryStore: repositoryStore,
            settingsModel: settingsModel
        )
    }
}
