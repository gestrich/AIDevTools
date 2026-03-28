import AIOutputSDK
import AnthropicSDK
import ClaudeCLISDK
import CodexCLISDK
import EvalSDK
import Foundation
import ProviderRegistryService

func makeProviderRegistry() -> ProviderRegistry {
    var providers: [any AIClient] = [
        ClaudeCLIClient(),
        CodexCLIClient(),
    ]
    if let client = makeAnthropicClientIfAvailable() {
        providers.append(client)
    }
    return ProviderRegistry(providers: providers)
}

func makeEvalRegistry(debug: Bool = false) -> EvalProviderRegistry {
    let claude = ClaudeCLIClient()
    let codex = CodexCLIClient()
    return EvalProviderRegistry(entries: [
        EvalProviderEntry(client: claude, adapter: ClaudeAdapter(client: claude, debug: debug)),
        EvalProviderEntry(client: codex, adapter: CodexAdapter(client: codex)),
    ])
}

func makeAnthropicClientIfAvailable() -> AnthropicAIClient? {
    guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty else {
        return nil
    }
    return AnthropicAIClient(apiClient: AnthropicAPIClient(apiKey: key))
}
