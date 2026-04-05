import Foundation

public struct MaintenanceCursorScope: Codable, Sendable {
    public let from: String
    public let to: String?

    public init(from: String, to: String? = nil) {
        self.from = from
        self.to = to
    }
}
