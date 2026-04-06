import AIOutputSDK
import AnthropicSDK
import ClaudeCLISDK
import CodexCLISDK
import CredentialService
import Foundation
import ProviderRegistryService

/// Resolves GitHub credentials for local CLI commands.
///
/// Sets GH_TOKEN in the process environment so child processes (e.g. `gh` CLI, Claude subprocess)
/// inherit the token. Returns the environment dict for the caller to pass to GitClient, and the
/// CredentialResolver so callers can also build a provider registry.
public func resolveGitHubCredentials(
    githubAccount: String?
) -> (gitEnvironment: [String: String]?, resolver: CredentialResolver) {
    let service = SecureSettingsService()
    // Swallowing intentionally: credential account enumeration failure is non-fatal — fall back to "default".
    let account = githubAccount ?? (try? service.listCredentialAccounts())?.first ?? "default"
    let resolver = CredentialResolver(settingsService: service, githubAccount: account)
    guard case .token(let token) = resolver.getGitHubAuth() else {
        return (nil, resolver)
    }
    setenv("GH_TOKEN", token, 1)
    return (["GH_TOKEN": token], resolver)
}

public func makeProviderRegistry(credentialResolver: CredentialResolver) -> ProviderRegistry {
    var providers: [any AIClient] = [ClaudeProvider(), CodexProvider()]
    if let key = credentialResolver.getAnthropicKey(), !key.isEmpty {
        providers.append(AnthropicProvider(apiClient: AnthropicAPIClient(apiKey: key)))
    }
    return ProviderRegistry(providers: providers)
}
