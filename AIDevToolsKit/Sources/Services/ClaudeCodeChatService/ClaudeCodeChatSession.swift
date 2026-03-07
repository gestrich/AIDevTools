import Foundation

public struct SessionState: Sendable, Equatable {
    public let workingDirectory: String
    public var messages: [ClaudeCodeChatMessage]
    public var sessionId: String?
    public var hasStartedSession: Bool

    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
        self.messages = []
        self.sessionId = nil
        self.hasStartedSession = false
    }

    public init(
        workingDirectory: String,
        messages: [ClaudeCodeChatMessage],
        sessionId: String?,
        hasStartedSession: Bool = true
    ) {
        self.workingDirectory = workingDirectory
        self.messages = messages
        self.sessionId = sessionId
        self.hasStartedSession = hasStartedSession
    }
}

public struct QueuedMessage: Identifiable, Sendable {
    public let id: UUID
    public let content: String
    public let images: [ImageAttachment]
    public let timestamp: Date

    public init(id: UUID = UUID(), content: String, images: [ImageAttachment] = [], timestamp: Date = Date()) {
        self.id = id
        self.content = content
        self.images = images
        self.timestamp = timestamp
    }
}

public struct ClaudeSession: Identifiable, Sendable {
    public let id: String
    public let summary: String
    public let lastModified: Date

    public init(id: String, summary: String, lastModified: Date) {
        self.id = id
        self.summary = summary
        self.lastModified = lastModified
    }
}

public struct SessionDetails: Sendable {
    public let session: ClaudeSession
    public let cwd: String?
    public let gitBranch: String?
    public let rawJsonLines: [String]

    public init(session: ClaudeSession, cwd: String?, gitBranch: String?, rawJsonLines: [String]) {
        self.session = session
        self.cwd = cwd
        self.gitBranch = gitBranch
        self.rawJsonLines = rawJsonLines
    }
}
