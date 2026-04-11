import AIOutputSDK
import AnthropicSDK
import ClaudeCLISDK
import CodexCLISDK
import CredentialService
import DataPathsService
import Foundation
import SettingsService

public struct SharedCompositionRoot {
    public let credentialResolver: CredentialResolver
    public let dataPathsService: DataPathsService
    public let evalProviderRegistry: EvalProviderRegistry
    public let providerRegistry: ProviderRegistry
    public let settingsService: SettingsService

    public static func create() throws -> SharedCompositionRoot {
        let secureSettings = SecureSettingsService()
        // Swallowing intentionally: credential account enumeration failure is non-fatal — fall back to "default".
        let account = (try? secureSettings.listCredentialAccounts())?.first ?? "default"
        let credentialResolver = CredentialResolver(settingsService: secureSettings, githubAccount: account)
        return try create(credentialResolver: credentialResolver)
    }

    public static func create(credentialResolver: CredentialResolver) throws -> SharedCompositionRoot {
        let dataPathsService = try DataPathsService(rootPath: AppPreferences().dataPath() ?? AppPreferences.defaultDataPath)
        try MigrateDataPathsUseCase(dataPathsService: dataPathsService).run()
        let settingsService = try SettingsService(dataPathsService: dataPathsService)
        let sessionsDirectory = try dataPathsService.path(for: .anthropicSessions)
        let providerRegistry = buildProviderRegistry(credentialResolver: credentialResolver, sessionsDirectory: sessionsDirectory)
        return SharedCompositionRoot(
            credentialResolver: credentialResolver,
            dataPathsService: dataPathsService,
            evalProviderRegistry: buildEvalProviderRegistry(),
            providerRegistry: providerRegistry,
            settingsService: settingsService
        )
    }

    public static func buildProviderRegistry(credentialResolver: CredentialResolver, sessionsDirectory: URL) -> ProviderRegistry {
        buildProviderRegistry(anthropicAPIKey: credentialResolver.getAnthropicKey(), sessionsDirectory: sessionsDirectory)
    }

    public static func buildProviderRegistry(anthropicAPIKey: String?, sessionsDirectory: URL, includeCodex: Bool = true, includeAnthropicAPI: Bool = true) -> ProviderRegistry {
        var providers: [any AIClient] = [ClaudeProvider()]
        if includeCodex {
            providers.append(CodexProvider())
        }
        if includeAnthropicAPI, let key = anthropicAPIKey, !key.isEmpty {
            providers.append(AnthropicProvider(apiClient: AnthropicAPIClient(apiKey: key), sessionsDirectory: sessionsDirectory))
        }
        return ProviderRegistry(providers: providers)
    }

    public static func buildEvalProviderRegistry() -> EvalProviderRegistry {
        EvalProviderRegistry(entries: [
            EvalProviderEntry(client: ClaudeProvider()),
            EvalProviderEntry(client: CodexProvider()),
        ])
    }
}
