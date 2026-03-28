import Foundation

public struct ChatSession: Identifiable, Sendable {
    public let id: String
    public let lastModified: Date
    public let summary: String

    public init(id: String, lastModified: Date, summary: String) {
        self.id = id
        self.lastModified = lastModified
        self.summary = summary
    }
}

public struct ChatSessionMessage: Sendable {
    public let content: String
    public let role: ChatSessionMessageRole

    public enum ChatSessionMessageRole: Sendable {
        case assistant
        case user
    }

    public init(content: String, role: ChatSessionMessageRole) {
        self.content = content
        self.role = role
    }
}

public struct SessionDetails: Sendable {
    public let cwd: String?
    public let gitBranch: String?
    public let rawJsonLines: [String]
    public let session: ChatSession

    public init(cwd: String?, gitBranch: String?, rawJsonLines: [String], session: ChatSession) {
        self.cwd = cwd
        self.gitBranch = gitBranch
        self.rawJsonLines = rawJsonLines
        self.session = session
    }
}

