import Foundation

public struct Conversation: Sendable, Identifiable {
    public let createdDate: Date
    public let id: UUID
    public var lastModifiedDate: Date
    public var messages: [ChatMessageRecord]
    public var sessionId: String?
    public var title: String?

    public init(
        createdDate: Date = Date(),
        id: UUID = UUID(),
        lastModifiedDate: Date = Date(),
        messages: [ChatMessageRecord] = [],
        sessionId: String? = nil,
        title: String? = nil
    ) {
        self.createdDate = createdDate
        self.id = id
        self.lastModifiedDate = lastModifiedDate
        self.messages = messages
        self.sessionId = sessionId
        self.title = title
    }
}
