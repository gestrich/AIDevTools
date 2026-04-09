import CredentialService
import Foundation

/// Resolves GitHub credentials for local CLI commands.
///
/// Sets GH_TOKEN in the process environment so child processes (e.g. `gh` CLI, Claude subprocess)
/// inherit the token. Use resolver.gitEnvironment to pass the env dict to GitClient.
///
/// When `githubToken` is provided it is used directly with no keychain or env fallback.
@discardableResult
public func resolveGitHubCredentials(
    githubAccount: String?,
    githubToken: String? = nil
) -> CredentialResolver {
    let resolver: CredentialResolver
    if let githubToken {
        resolver = CredentialResolver.withExplicitToken(githubToken)
    } else {
        let service = SecureSettingsService()
        // Swallowing intentionally: credential account enumeration failure is non-fatal — fall back to "default".
        let account = githubAccount ?? (try? service.listCredentialAccounts())?.first ?? "default"
        resolver = CredentialResolver(settingsService: service, githubAccount: account)
    }
    if case .token(let token) = resolver.getGitHubAuth() {
        setenv("GH_TOKEN", token, 1)
    }
    return resolver
}
