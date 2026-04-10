import AIOutputSDK
import AnthropicSDK
import ArgumentParser
import ClaudeCLISDK
import CodexCLISDK
import CredentialService
import DataPathsService
import Foundation
import ProviderRegistryService

func makeProviderRegistry(credentialResolver: CredentialResolver) -> ProviderRegistry {
    let dataRoot = AppPreferences().dataPath() ?? AppPreferences.defaultDataPath
    let sessionsDirectory = dataRoot.appending(path: ServicePath.anthropicSessions.relativePath)
    var providers: [any AIClient] = [ClaudeProvider(), CodexProvider()]
    if let key = credentialResolver.getAnthropicKey(), !key.isEmpty {
        providers.append(AnthropicProvider(apiClient: AnthropicAPIClient(apiKey: key), sessionsDirectory: sessionsDirectory))
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

func resolveClient(named providerName: String?, from registry: ProviderRegistry) throws -> any AIClient {
    if let providerName {
        guard let client = registry.client(named: providerName) else {
            print("Unknown provider '\(providerName)'. Available: \(registry.providerNames.joined(separator: ", "))")
            throw ExitCode.failure
        }
        return client
    } else {
        guard let client = registry.defaultClient else {
            print("No providers registered.")
            throw ExitCode.failure
        }
        return client
    }
}
