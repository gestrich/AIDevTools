import ClaudeCLISDK
import CodexCLISDK
import CredentialService
import DataPathsService
import Foundation
import GitSDK
import ProviderRegistryService
import RepositorySDK
import SettingsService

@MainActor
struct CompositionRoot {
    let dataPathsService: DataPathsService
    let evalProviderRegistry: EvalProviderRegistry
    let gitClientFactory: @Sendable (String?) -> GitClient
    let providerModel: ProviderModel
    let settingsModel: SettingsModel
    let settingsService: SettingsService

    static func create() throws -> CompositionRoot {
        let settingsModel = SettingsModel()
        let dataPathsService = try DataPathsService(rootPath: settingsModel.dataPath)
        try MigrateDataPathsUseCase(dataPathsService: dataPathsService).run()

        let settingsService = try SettingsService(dataPathsService: dataPathsService)

        let evalProviderRegistry = EvalProviderRegistry(entries: [
            EvalProviderEntry(client: ClaudeProvider()),
            EvalProviderEntry(client: CodexProvider()),
        ])

        writeMCPConfig()

        let gitClientFactory: @Sendable (String?) -> GitClient = { account in
            guard let account else { return GitClient() }
            let resolver = CredentialResolver(
                settingsService: SecureSettingsService(),
                githubAccount: account
            )
            guard case .token(let token) = resolver.getGitHubAuth() else { return GitClient() }
            setenv("GH_TOKEN", token, 1)
            return GitClient(environment: ["GH_TOKEN": token])
        }

        return CompositionRoot(
            dataPathsService: dataPathsService,
            evalProviderRegistry: evalProviderRegistry,
            gitClientFactory: gitClientFactory,
            providerModel: ProviderModel(),
            settingsModel: settingsModel,
            settingsService: settingsService
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
        // Swallowing intentionally: MCP config is optional; if the write fails the app continues without MCP.
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? config.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
