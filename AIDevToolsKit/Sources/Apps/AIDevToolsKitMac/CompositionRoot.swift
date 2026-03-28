import AIOutputSDK
import ClaudeCLISDK
import CodexCLISDK
import DataPathsService
import EvalSDK
import EvalService
import PlanRunnerService
import ProviderRegistryService
import RepositorySDK

@MainActor
struct CompositionRoot {
    let dataPathsService: DataPathsService
    let evalSettingsStore: EvalRepoSettingsStore
    let planSettingsStore: PlanRepoSettingsStore
    let providerRegistry: ProviderRegistry
    let evalProviderRegistry: EvalProviderRegistry
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
        let planSettingsStore = PlanRepoSettingsStore(
            filePath: try dataPathsService.path(for: .planSettings).appending(path: "plan-settings.json")
        )

        let claude = ClaudeCLIClient()
        let codex = CodexCLIClient()

        let providerRegistry = ProviderRegistry(providers: [claude, codex])

        let evalProviderRegistry = EvalProviderRegistry(entries: [
            EvalProviderEntry(client: claude, adapter: ClaudeAdapter(client: claude)),
            EvalProviderEntry(client: codex, adapter: CodexAdapter(client: codex)),
        ])

        return CompositionRoot(
            dataPathsService: dataPathsService,
            evalSettingsStore: evalSettingsStore,
            planSettingsStore: planSettingsStore,
            providerRegistry: providerRegistry,
            evalProviderRegistry: evalProviderRegistry,
            repositoryStore: repositoryStore,
            settingsModel: settingsModel
        )
    }
}
