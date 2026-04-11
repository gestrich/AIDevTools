import AIOutputSDK
import ClaudeCLISDK
import CodexCLISDK
import CredentialService
import DataPathsService
import Foundation
import ProviderRegistryService

public func makeProviderRegistry(credentialResolver: CredentialResolver) -> ProviderRegistry {
    let providers: [any AIClient] = [ClaudeProvider(), CodexProvider()]
    return ProviderRegistry(providers: providers)
}
