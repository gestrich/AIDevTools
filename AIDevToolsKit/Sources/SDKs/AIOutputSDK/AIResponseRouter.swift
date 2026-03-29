import Foundation

/// Type-erased router that dispatches structured AI responses to typed handlers.
public final class AIResponseRouter: AIResponseHandling, @unchecked Sendable {
    private struct Route {
        let descriptor: AIResponseDescriptor
        let handle: @Sendable (Data) async throws -> String?
    }

    private var routes: [String: Route] = [:]
    private let lock = NSLock()

    public init() {}

    /// Register a route for a named structured output.
    public func addRoute<T: Decodable & Sendable>(
        _ descriptor: AIResponseDescriptor,
        type: T.Type,
        handler: @escaping @Sendable (T) async -> String?
    ) {
        let route = Route(descriptor: descriptor) { data in
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return await handler(decoded)
        }
        lock.withLock { routes[descriptor.name] = route }
    }

    // MARK: - AIResponseHandling

    public var responseDescriptors: [AIResponseDescriptor] {
        lock.withLock { routes.values.map(\.descriptor).sorted { $0.name < $1.name } }
    }

    public func handleResponse(name: String, json: Data) async throws -> String? {
        let route = lock.withLock { routes[name] }
        return try await route?.handle(json)
    }
}
