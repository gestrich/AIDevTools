import AIOutputSDK
import AnthropicSDK
import ClaudeCLISDK
import CodexCLISDK
import CredentialService
import Foundation
import ProviderRegistryService

func makeProviderRegistry(credentialResolver: CredentialResolver) -> ProviderRegistry {
    var providers: [any AIClient] = [ClaudeProvider(), CodexProvider()]
    if let key = credentialResolver.getAnthropicKey(), !key.isEmpty {
        providers.append(AnthropicProvider(apiClient: AnthropicAPIClient(apiKey: key)))
    }
    return ProviderRegistry(providers: providers)
}

func makeProviderRegistry() -> ProviderRegistry {
    let service = SecureSettingsService()
    let account = (try? service.listCredentialAccounts())?.first ?? "default"
    let resolver = CredentialResolver(settingsService: service, githubAccount: account)
    return makeProviderRegistry(credentialResolver: resolver)
}

func makeEvalRegistry(debug: Bool = false) -> EvalProviderRegistry {
    EvalProviderRegistry(entries: [
        EvalProviderEntry(client: ClaudeProvider()),
        EvalProviderEntry(client: CodexProvider()),
    ])
}
