import Foundation

public struct GitHubCheckRun: Codable, Sendable {
    public let name: String
    public let status: String
    public let conclusion: String?

    public init(name: String, status: String, conclusion: String? = nil) {
        self.name = name
        self.status = status
        self.conclusion = conclusion
    }

    public var isPassing: Bool { conclusion == "success" }
    public var isFailing: Bool { conclusion == "failure" }
}
