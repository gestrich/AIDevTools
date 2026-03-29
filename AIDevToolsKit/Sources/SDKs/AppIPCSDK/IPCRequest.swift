import Foundation

public struct IPCRequest: Codable, Sendable {
    public let query: String

    public init(query: String) {
        self.query = query
    }
}
