import Foundation

public struct RepoMatch: Codable, Sendable {
    public let repoId: String
    public let interpretedRequest: String

    public init(repoId: String, interpretedRequest: String) {
        self.repoId = repoId
        self.interpretedRequest = interpretedRequest
    }
}
