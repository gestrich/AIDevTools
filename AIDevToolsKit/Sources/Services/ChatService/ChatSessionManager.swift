import AIOutputSDK
import Foundation

public actor ChatSessionManager {
    private let client: any AIClient
    private var conversations: [UUID: Conversation] = [:]

    public init(client: any AIClient) {
        self.client = client
    }

    public func createConversation(title: String? = nil) -> Conversation {
        let conversation = Conversation(title: title)
        conversations[conversation.id] = conversation
        return conversation
    }

    public func conversation(id: UUID) -> Conversation? {
        conversations[id]
    }

    public func allConversations() -> [Conversation] {
        Array(conversations.values).sorted { $0.lastModifiedDate > $1.lastModifiedDate }
    }

    public func send(
        message: String,
        conversationId: UUID,
        options: AIClientOptions = AIClientOptions(),
        onEvent: @escaping @Sendable (ChatStreamEvent) -> Void
    ) async throws {
        guard var conversation = conversations[conversationId] else {
            throw ChatSessionError.conversationNotFound(conversationId)
        }

        let userMessage = ChatMessageRecord(content: message, isUser: true)
        conversation.messages.append(userMessage)
        conversations[conversationId] = conversation

        var clientOptions = options
        clientOptions.sessionId = conversation.sessionId

        let result = try await client.run(
            prompt: message,
            options: clientOptions,
            onOutput: { text in
                onEvent(.textDelta(text))
            }
        )

        let assistantMessage = ChatMessageRecord(content: result.stdout, isUser: false)
        conversation.messages.append(assistantMessage)
        conversation.sessionId = result.sessionId
        conversation.lastModifiedDate = Date()
        conversations[conversationId] = conversation

        onEvent(.completed(fullText: result.stdout))
    }
}

public enum ChatSessionError: Error, LocalizedError {
    case conversationNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .conversationNotFound(let id):
            return "Conversation not found: \(id)"
        }
    }
}
