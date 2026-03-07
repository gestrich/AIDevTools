import Foundation
@preconcurrency import SwiftAnthropic

public struct ConversationContext: Sendable {
    public var messages: [MessageParameter.Message]
    public var initialDocumentContent: String?

    public init(messages: [MessageParameter.Message] = [], initialDocumentContent: String? = nil) {
        self.messages = messages
        self.initialDocumentContent = initialDocumentContent
    }

    public mutating func addUserMessage(_ content: String) {
        messages.append(MessageParameter.Message(
            role: .user,
            content: .text(content)
        ))
    }

    public mutating func addAssistantMessage(_ content: String) {
        messages.append(MessageParameter.Message(
            role: .assistant,
            content: .text(content)
        ))
    }

    public mutating func addAssistantMessage(text: String, toolUses: [MessageParameter.Message.Content.ContentObject]) {
        var content: [MessageParameter.Message.Content.ContentObject] = []
        if !text.isEmpty {
            content.append(.text(text))
        }
        content.append(contentsOf: toolUses)

        messages.append(MessageParameter.Message(
            role: .assistant,
            content: .list(content)
        ))
    }

    public mutating func addToolResults(_ results: [MessageParameter.Message.Content.ContentObject]) {
        messages.append(MessageParameter.Message(
            role: .user,
            content: .list(results)
        ))
    }
}
