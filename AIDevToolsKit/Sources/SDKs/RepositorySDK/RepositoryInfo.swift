import Foundation

public struct RepositoryInfo: Codable, Identifiable, Sendable {
    public let id: UUID
    public let path: URL
    public let name: String
    public var description: String?
    public var githubUser: String?
    public var recentFocus: String?
    public var skills: [String]?
    public var architectureDocs: [String]?
    public var verification: Verification?
    public var pullRequest: PullRequestConfig?

    public init(
        id: UUID = UUID(),
        path: URL,
        name: String? = nil,
        description: String? = nil,
        githubUser: String? = nil,
        recentFocus: String? = nil,
        skills: [String]? = nil,
        architectureDocs: [String]? = nil,
        verification: Verification? = nil,
        pullRequest: PullRequestConfig? = nil
    ) {
        self.id = id
        self.path = path
        self.name = name ?? path.lastPathComponent
        self.description = description
        self.githubUser = githubUser
        self.recentFocus = recentFocus
        self.skills = skills
        self.architectureDocs = architectureDocs
        self.verification = verification
        self.pullRequest = pullRequest
    }
}

public struct Verification: Codable, Sendable, Equatable {
    public let commands: [String]
    public let notes: String?

    public init(commands: [String], notes: String? = nil) {
        self.commands = commands
        self.notes = notes
    }
}

public struct PullRequestConfig: Codable, Sendable, Equatable {
    public let baseBranch: String
    public let branchNamingConvention: String
    public let template: String?
    public let notes: String?

    public init(
        baseBranch: String,
        branchNamingConvention: String,
        template: String? = nil,
        notes: String? = nil
    ) {
        self.baseBranch = baseBranch
        self.branchNamingConvention = branchNamingConvention
        self.template = template
        self.notes = notes
    }
}
