import ClaudeCLISDK
import CodexCLISDK
import DataPathsService
import Foundation
import EvalService
import MarkdownPlannerService
import PRRadarConfigService
import ProviderRegistryService
import RepositorySDK

@MainActor
struct CompositionRoot {
    let dataPathsService: DataPathsService
    let evalSettingsStore: EvalRepoSettingsStore
    let evalProviderRegistry: EvalProviderRegistry
    let planSettingsStore: MarkdownPlannerRepoSettingsStore
    let prradarSettingsStore: PRRadarRepoSettingsStore
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
        let prradarSettingsStore = PRRadarRepoSettingsStore(
            filePath: try dataPathsService.path(for: .prradarSettings).appending(path: "prradar-settings.json")
        )

        let evalProviderRegistry = EvalProviderRegistry(entries: [
            EvalProviderEntry(client: ClaudeProvider()),
            EvalProviderEntry(client: CodexProvider()),
        ])

        writeMCPConfig()

        return CompositionRoot(
            dataPathsService: dataPathsService,
            evalSettingsStore: evalSettingsStore,
            evalProviderRegistry: evalProviderRegistry,
            planSettingsStore: planSettingsStore,
            prradarSettingsStore: prradarSettingsStore,
            providerModel: ProviderModel(),
            repositoryStore: repositoryStore,
            settingsModel: settingsModel
        )
    }

    private static func writeMCPConfig() {
        let config = """
        {
          "mcpServers": {
            "ai-dev-tools-kit": {
              "command": "ai-dev-tools-kit",
              "args": ["mcp"]
            }
          }
        }
        """
        let fileURL = DataPathsService.mcpConfigFileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? config.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
