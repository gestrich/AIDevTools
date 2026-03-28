import AIOutputSDK
import Foundation

public struct ChatProviderOptions: Sendable {
    public var dangerouslySkipPermissions: Bool
    public var model: String?
    public var sessionId: String?
    public var systemPrompt: String?
    public var workingDirectory: String?

    public init(
        dangerouslySkipPermissions: Bool = false,
        model: String? = nil,
        sessionId: String? = nil,
        systemPrompt: String? = nil,
        workingDirectory: String? = nil
    ) {
        self.dangerouslySkipPermissions = dangerouslySkipPermissions
        self.model = model
        self.sessionId = sessionId
        self.systemPrompt = systemPrompt
        self.workingDirectory = workingDirectory
    }
}

public struct ChatProviderResult: Sendable {
    public let content: String
    public let sessionId: String?

    public init(content: String, sessionId: String?) {
        self.content = content
        self.sessionId = sessionId
    }
}

public protocol ChatProvider: Sendable {
    var displayName: String { get }
    var name: String { get }
    var supportsSessionHistory: Bool { get }

    func cancel() async
    func getSessionDetails(sessionId: String, summary: String, lastModified: Date, workingDirectory: String) -> SessionDetails?
    func listSessions(workingDirectory: String) async -> [ChatSession]
    func loadSessionMessages(sessionId: String, workingDirectory: String) async -> [ChatSessionMessage]
    func sendMessage(
        _ message: String,
        images: [ImageAttachment],
        options: ChatProviderOptions,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> ChatProviderResult
}

extension ChatProvider {
    public var supportsSessionHistory: Bool { false }

    public func cancel() async {}

    public func getSessionDetails(sessionId: String, summary: String, lastModified: Date, workingDirectory: String) -> SessionDetails? { nil }

    public func listSessions(workingDirectory: String) async -> [ChatSession] { [] }

    public func loadSessionMessages(sessionId: String, workingDirectory: String) async -> [ChatSessionMessage] { [] }
}
