import AIOutputSDK
import AnthropicSDK
import ClaudeCLISDK
import CodexCLISDK
import CredentialService
import Foundation
import ProviderRegistryService

func makeProviderRegistry() -> ProviderRegistry {
    var providers: [any AIClient] = [
        ClaudeProvider(),
        CodexProvider(),
    ]
    if let client = makeAnthropicClientIfAvailable() {
        providers.append(client)
    }
    return ProviderRegistry(providers: providers)
}

func makeEvalRegistry(debug: Bool = false) -> EvalProviderRegistry {
    EvalProviderRegistry(entries: [
        EvalProviderEntry(client: ClaudeProvider()),
        EvalProviderEntry(client: CodexProvider()),
    ])
}

func makeAnthropicClientIfAvailable() -> AnthropicProvider? {
    let service = CredentialSettingsService()
    let account = (try? service.listCredentialAccounts())?.first ?? "default"
    let resolver = CredentialResolver(settingsService: service, githubAccount: account)
    guard let key = resolver.getAnthropicKey(), !key.isEmpty else {
        return nil
    }
    return AnthropicProvider(apiClient: AnthropicAPIClient(apiKey: key))
}
