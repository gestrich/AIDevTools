import CredentialService
import DataPathsService
import Foundation
import GitSDK
import ProviderRegistryService
import SettingsService

@MainActor
struct CompositionRoot {
    let dataPathsService: DataPathsService
    let evalProviderRegistry: EvalProviderRegistry
    let gitClientFactory: @Sendable (String?) -> GitClient
    let mcpModel: MCPModel
    let providerModel: ProviderModel
    let settingsModel: SettingsModel
    let settingsService: SettingsService

    static func create() throws -> CompositionRoot {
        let shared = try SharedCompositionRoot.create()
        let settingsModel = SettingsModel()

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

        let anthropicSessionsDirectory = try shared.dataPathsService.path(for: .anthropicSessions)
        let mcpModel = MCPModel(settingsModel: settingsModel)
        mcpModel.writeMCPConfigIfNeeded()

        return CompositionRoot(
            dataPathsService: shared.dataPathsService,
            evalProviderRegistry: shared.evalProviderRegistry,
            gitClientFactory: gitClientFactory,
            mcpModel: mcpModel,
            providerModel: ProviderModel(sessionsDirectory: anthropicSessionsDirectory),
            settingsModel: settingsModel,
            settingsService: shared.settingsService
        )
    }

}
