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
    var providers: [any AIClient] = [ClaudeProvider(), CodexProvider()]
    let sessionsDirectory = dataRoot.appending(path: ServicePath.anthropicSessions.relativePath)
    if let key = credentialResolver.getAnthropicKey(), !key.isEmpty {
        providers.append(AnthropicProvider(apiClient: AnthropicAPIClient(apiKey: key), sessionsDirectory: sessionsDirectory))
    }
    return ProviderRegistry(providers: providers)
}
