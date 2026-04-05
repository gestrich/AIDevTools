import Foundation

public struct PhaseResult: Codable, Sendable {
    public let success: Bool

    public init(success: Bool) {
        self.success = success
    }
}
