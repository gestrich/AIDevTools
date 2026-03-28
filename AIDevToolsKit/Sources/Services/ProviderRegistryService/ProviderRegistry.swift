import AIOutputSDK
import EvalSDK
import EvalService

public struct ProviderRegistry: Sendable {
    public let providers: [any AIClient]

    public init(providers: [any AIClient]) {
        self.providers = providers
    }

    public var providerNames: [String] {
        providers.map(\.name)
    }

    public func client(named name: String) -> (any AIClient)? {
        providers.first { $0.name == name }
    }
}

public struct EvalProviderEntry: Sendable {
    public let client: any AIClient
    public let adapter: any ProviderAdapterProtocol

    public var provider: Provider { Provider(client: client) }
    public var name: String { client.name }
    public var displayName: String { client.displayName }

    public init(client: any AIClient, adapter: any ProviderAdapterProtocol) {
        self.client = client
        self.adapter = adapter
    }
}

public struct EvalProviderRegistry: Sendable {
    public let entries: [EvalProviderEntry]

    public init(entries: [EvalProviderEntry]) {
        self.entries = entries
    }

    public func filtered(by names: [String]?) -> [EvalProviderEntry] {
        guard let names, !names.isEmpty else { return entries }
        return entries.filter { names.contains($0.name) }
    }
}
