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
        let evalSettingsStore = EvalRepoSettingsStore(repositoryStore: repositoryStore)
        let planSettingsStore = MarkdownPlannerRepoSettingsStore(repositoryStore: repositoryStore)
        let prradarSettingsStore = PRRadarRepoSettingsStore(repositoryStore: repositoryStore)

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
        // Prefer the CLI binary next to the app bundle (Xcode builds), then ~/.local/bin, then PATH.
        let siblingURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("ai-dev-tools-kit")
        let localBinURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/ai-dev-tools-kit")
        let command: String
        if FileManager.default.fileExists(atPath: siblingURL.path) {
            command = siblingURL.path
        } else if FileManager.default.fileExists(atPath: localBinURL.path) {
            command = localBinURL.path
        } else {
            command = "ai-dev-tools-kit"
        }

        let config = """
        {
          "mcpServers": {
            "ai-dev-tools-kit": {
              "command": "\(command)",
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
