import Foundation

/// Protocol for receiving and handling structured AI outputs.
/// The handler defines what responses the AI can produce and processes them when they arrive.
public protocol AIResponseHandling: Sendable {
    var responseDescriptors: [AIResponseDescriptor] { get }

    /// Handle a structured response from the AI.
    /// - Returns: A reply string (for queries), or nil (for fire-and-forget actions).
    func handleResponse(name: String, json: Data) async throws -> String?
}
