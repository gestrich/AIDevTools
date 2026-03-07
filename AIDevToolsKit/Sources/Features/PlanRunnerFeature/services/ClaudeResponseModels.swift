import Foundation

public struct RepoMatch: Codable, Sendable {
    public let repoId: String
    public let interpretedRequest: String

    public init(repoId: String, interpretedRequest: String) {
        self.repoId = repoId
        self.interpretedRequest = interpretedRequest
    }
}

public struct GeneratedPlan: Codable, Sendable {
    public let planContent: String
    public let filename: String

    public init(planContent: String, filename: String) {
        self.planContent = planContent
        self.filename = filename
    }
}

public struct PhaseResult: Codable, Sendable {
    public let success: Bool

    public init(success: Bool) {
        self.success = success
    }
}
