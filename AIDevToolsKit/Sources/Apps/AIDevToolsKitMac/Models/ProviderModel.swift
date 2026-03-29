import AIOutputSDK
import AnthropicSDK
import ClaudeCLISDK
import CodexCLISDK
import CredentialService
import Foundation
import ProviderRegistryService

extension Notification.Name {
    static let credentialsDidChange = Notification.Name("credentialsDidChange")
}

@MainActor @Observable
final class ProviderModel {
    private(set) var providerRegistry: ProviderRegistry
    private let anthropicAPIKeySource: @Sendable () -> String?

    init(anthropicAPIKeySource: @escaping @Sendable () -> String? = {
        let service = CredentialSettingsService()
        let account = (try? service.listCredentialAccounts())?.first ?? "default"
        return CredentialResolver(settingsService: service, githubAccount: account).getAnthropicKey()
    }) {
        self.anthropicAPIKeySource = anthropicAPIKeySource
        self.providerRegistry = Self.buildRegistry(anthropicAPIKey: anthropicAPIKeySource())
    }

    func refreshProviders() {
        self.providerRegistry = Self.buildRegistry(anthropicAPIKey: anthropicAPIKeySource())
    }

    private static func buildRegistry(anthropicAPIKey: String?) -> ProviderRegistry {
        var providers: [any AIClient] = [ClaudeProvider(), CodexProvider()]
        if let key = anthropicAPIKey, !key.isEmpty {
            providers.append(AnthropicProvider(apiClient: AnthropicAPIClient(apiKey: key)))
        }
        return ProviderRegistry(providers: providers)
    }
}
