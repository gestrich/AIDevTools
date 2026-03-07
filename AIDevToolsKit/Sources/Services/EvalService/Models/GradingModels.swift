import Foundation

public struct RubricPayload: Codable, Sendable {
    public let overallPass: Bool
    public let score: Int
    public let checks: [RubricCheck]

    public init(overallPass: Bool, score: Int, checks: [RubricCheck]) {
        self.overallPass = overallPass
        self.score = score
        self.checks = checks
    }
}

public struct RubricCheck: Codable, Sendable {
    public let id: String
    public let pass: Bool
    public let notes: String

    public init(id: String, pass: Bool, notes: String) {
        self.id = id
        self.pass = pass
        self.notes = notes
    }
}
