import Foundation
import SwiftData

@Model
public final class ChatConversation {
    public var id = UUID()
    public var title: String = ""
    public var createdDate = Date()
    public var lastModifiedDate = Date()
    @Relationship(deleteRule: .cascade) public var messages: [ChatMessage]? = []

    public init(title: String = "New Conversation") {
        self.id = UUID()
        self.title = title
        self.createdDate = Date()
        self.lastModifiedDate = Date()
    }
}

@Model
public final class ChatMessage {
    public var id = UUID()
    public var content: String = ""
    public var isUser = false
    public var timestamp = Date()
    @Relationship(inverse: \ChatConversation.messages) public var conversation: ChatConversation?

    public init(content: String, isUser: Bool) {
        self.id = UUID()
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
    }
}
