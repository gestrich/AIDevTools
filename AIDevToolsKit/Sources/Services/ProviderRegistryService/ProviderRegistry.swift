import AIOutputSDK

public struct ProviderRegistry: Sendable {
    public let providers: [any AIClient]

    public init(providers: [any AIClient]) {
        self.providers = providers
    }

    public var defaultClient: (any AIClient)? {
        providers.first
    }

    public var providerNames: [String] {
        providers.map(\.name)
    }

    public func client(named name: String) -> (any AIClient)? {
        providers.first { $0.name == name }
    }
}

public struct EvalProviderEntry: Sendable {
    public let client: any AIClient & EvalCapable

    public var provider: Provider { Provider(client: client) }
    public var name: String { client.name }
    public var displayName: String { client.displayName }

    public init(client: any AIClient & EvalCapable) {
        self.client = client
    }
}

public struct EvalProviderRegistry: Sendable {
    public let entries: [EvalProviderEntry]

    public init(entries: [EvalProviderEntry]) {
        self.entries = entries
    }

    public static func from(_ registry: ProviderRegistry) -> EvalProviderRegistry {
        let entries = registry.providers.compactMap { client -> EvalProviderEntry? in
            guard let evalClient = client as? any AIClient & EvalCapable else { return nil }
            return EvalProviderEntry(client: evalClient)
        }
        return EvalProviderRegistry(entries: entries)
    }

    public var defaultEntry: EvalProviderEntry? {
        entries.first
    }

    public func filtered(by names: [String]?) -> [EvalProviderEntry] {
        guard let names, !names.isEmpty else { return entries }
        return entries.filter { names.contains($0.name) }
    }
}
