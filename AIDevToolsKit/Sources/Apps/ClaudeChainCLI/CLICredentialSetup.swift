import AIOutputSDK
import AnthropicSDK
import ClaudeCLISDK
import CodexCLISDK
import CredentialService
import DataPathsService
import Foundation
import ProviderRegistryService

public func makeProviderRegistry(credentialResolver: CredentialResolver) -> ProviderRegistry {
    let dataRoot = AppPreferences().dataPath() ?? AppPreferences.defaultDataPath
    let sessionsDirectory = dataRoot.appending(path: ServicePath.anthropicSessions.relativePath)
    var providers: [any AIClient] = [ClaudeProvider(), CodexProvider()]
    if let key = credentialResolver.getAnthropicKey(), !key.isEmpty {
        providers.append(AnthropicProvider(apiClient: AnthropicAPIClient(apiKey: key), sessionsDirectory: sessionsDirectory))
    }
    return ProviderRegistry(providers: providers)
}
