import Foundation
import EvalService
import EvalSDK

struct MockProviderAdapter: ProviderAdapterProtocol {
    var providerCapabilities: ProviderCapabilities
    var result: ProviderResult
    var runHandler: (@Sendable (RunConfiguration) async throws -> ProviderResult)?

    init(
        capabilities: ProviderCapabilities = ProviderCapabilities(),
        result: ProviderResult = ProviderResult(provider: .claude)
    ) {
        self.providerCapabilities = capabilities
        self.result = result
    }

    func capabilities() -> ProviderCapabilities {
        providerCapabilities
    }

    func run(configuration: RunConfiguration, onOutput: (@Sendable (String) -> Void)? = nil) async throws -> ProviderResult {
        if let handler = runHandler {
            return try await handler(configuration)
        }
        return result
    }
}
