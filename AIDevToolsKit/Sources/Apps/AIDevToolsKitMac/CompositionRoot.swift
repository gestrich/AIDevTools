import DataPathsService
import EvalService
import PlanRunnerService
import RepositorySDK

@MainActor
struct CompositionRoot {
    let dataPathsService: DataPathsService
    let evalSettingsStore: EvalRepoSettingsStore
    let planSettingsStore: PlanRepoSettingsStore
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

        return CompositionRoot(
            dataPathsService: dataPathsService,
            evalSettingsStore: evalSettingsStore,
            planSettingsStore: planSettingsStore,
            repositoryStore: repositoryStore,
            settingsModel: settingsModel
        )
    }
}
