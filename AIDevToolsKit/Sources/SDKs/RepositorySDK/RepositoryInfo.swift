import Foundation

public struct RepositoryInfo: Codable, Identifiable, Sendable {
    public let id: UUID
    public let path: URL
    public let name: String
    public var credentialAccount: String?
    public var description: String?
    public var recentFocus: String?
    public var skills: [String]?
    public var architectureDocs: [String]?
    public var verification: Verification?
    public var pullRequest: PullRequestConfig?

    public init(
        id: UUID = UUID(),
        path: URL,
        name: String? = nil,
        credentialAccount: String? = nil,
        description: String? = nil,
        recentFocus: String? = nil,
        skills: [String]? = nil,
        architectureDocs: [String]? = nil,
        verification: Verification? = nil,
        pullRequest: PullRequestConfig? = nil
    ) {
        self.id = id
        self.path = path
        self.name = name ?? path.lastPathComponent
        self.credentialAccount = credentialAccount
        self.description = description
        self.recentFocus = recentFocus
        self.skills = skills
        self.architectureDocs = architectureDocs
        self.verification = verification
        self.pullRequest = pullRequest
    }

    public func with(id: UUID) -> RepositoryInfo {
        RepositoryInfo(
            id: id,
            path: path,
            name: name,
            credentialAccount: credentialAccount,
            description: description,
            recentFocus: recentFocus,
            skills: skills,
            architectureDocs: architectureDocs,
            verification: verification,
            pullRequest: pullRequest
        )
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
    public static let defaultBaseBranch = "main"
    public static let defaultBranchNamingConvention = "feature/description"

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

    /// Creates a config from raw form strings. Returns nil if all fields are empty.
    public static func from(
        baseBranch: String,
        branchNamingConvention: String,
        template: String,
        notes: String
    ) -> PullRequestConfig? {
        guard !baseBranch.isEmpty || !branchNamingConvention.isEmpty
            || !template.isEmpty || !notes.isEmpty else {
            return nil
        }
        return PullRequestConfig(
            baseBranch: baseBranch,
            branchNamingConvention: branchNamingConvention,
            template: template.isEmpty ? nil : template,
            notes: notes.isEmpty ? nil : notes
        )
    }
}
