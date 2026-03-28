import AIOutputSDK
import ClaudeCLISDK
import CodexCLISDK
import EvalSDK
import ProviderRegistryService

func makeProviderRegistry() -> ProviderRegistry {
    ProviderRegistry(providers: [
        ClaudeCLIClient(),
        CodexCLIClient(),
    ])
}

func makeEvalRegistry(debug: Bool = false) -> EvalProviderRegistry {
    let claude = ClaudeCLIClient()
    let codex = CodexCLIClient()
    return EvalProviderRegistry(entries: [
        EvalProviderEntry(client: claude, adapter: ClaudeAdapter(client: claude, debug: debug)),
        EvalProviderEntry(client: codex, adapter: CodexAdapter(client: codex)),
    ])
}
