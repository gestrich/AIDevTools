import Foundation

public struct ChatMessageRecord: Sendable, Identifiable {
    public let content: String
    public let id: UUID
    public let isUser: Bool
    public let timestamp: Date

    public init(content: String, id: UUID = UUID(), isUser: Bool, timestamp: Date = Date()) {
        self.content = content
        self.id = id
        self.isUser = isUser
        self.timestamp = timestamp
    }
}
