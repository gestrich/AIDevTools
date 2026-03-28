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

public protocol SessionListable {
    func listSessions(workingDirectory: String) async -> [ChatSession]
    func loadSessionMessages(sessionId: String, workingDirectory: String) async -> [ChatSessionMessage]
}
