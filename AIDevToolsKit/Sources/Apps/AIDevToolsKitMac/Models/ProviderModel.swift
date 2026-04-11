import CredentialService
import DataPathsService
import Foundation
import ProviderRegistryService

extension Notification.Name {
    static let credentialsDidChange = Notification.Name("credentialsDidChange")
}

@MainActor @Observable
final class ProviderModel {
    private(set) var providerRegistry: ProviderRegistry
    private let anthropicAPIKeySource: @Sendable () -> String?
    private let sessionsDirectory: URL

    init(
        sessionsDirectory: URL,
        anthropicAPIKeySource: @escaping @Sendable () -> String? = {
            let service = SecureSettingsService()
            let account = (try? service.listCredentialAccounts())?.first ?? "default"
            return CredentialResolver(settingsService: service, githubAccount: account).getAnthropicKey()
        }
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.anthropicAPIKeySource = anthropicAPIKeySource
        self.providerRegistry = Self.buildRegistry(anthropicAPIKey: anthropicAPIKeySource(), sessionsDirectory: sessionsDirectory)
    }

    func refreshProviders() {
        self.providerRegistry = Self.buildRegistry(anthropicAPIKey: anthropicAPIKeySource(), sessionsDirectory: sessionsDirectory)
    }

    private static func buildRegistry(anthropicAPIKey: String?, sessionsDirectory: URL) -> ProviderRegistry {
        let prefs = AppPreferences()
        return SharedCompositionRoot.buildProviderRegistry(
            anthropicAPIKey: anthropicAPIKey,
            sessionsDirectory: sessionsDirectory,
            includeCodex: prefs.isCodexEnabled(),
            includeAnthropicAPI: prefs.isAnthropicAPIEnabled()
        )
    }
}
