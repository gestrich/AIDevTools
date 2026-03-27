import AIOutputSDK
import Foundation
import SwiftData

@MainActor
public final class ConversationManager {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func createConversation(title: String = "New Conversation") -> ChatConversation? {
        let conversation = ChatConversation(title: title)
        modelContext.insert(conversation)

        do {
            try modelContext.save()
            return conversation
        } catch {
            print("Failed to create conversation: \(error)")
            return nil
        }
    }

    public func saveMessage(to conversation: ChatConversation, content: String, isUser: Bool) {
        let message = ChatMessage(content: content, isUser: isUser)
        message.conversation = conversation
        conversation.lastModifiedDate = Date()

        modelContext.insert(message)

        do {
            try modelContext.save()
        } catch {
            print("Failed to save message: \(error)")
        }
    }

    public func updateTitle(_ conversation: ChatConversation, title: String) {
        conversation.title = title

        do {
            try modelContext.save()
        } catch {
            print("Failed to update conversation title: \(error)")
        }
    }

    public func deleteConversation(_ conversation: ChatConversation) {
        modelContext.delete(conversation)

        do {
            try modelContext.save()
        } catch {
            print("Failed to delete conversation: \(error)")
        }
    }

    public func fetchConversations() -> [ChatConversation] {
        let descriptor = FetchDescriptor<ChatConversation>(
            sortBy: [SortDescriptor(\.lastModifiedDate, order: .reverse)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("Failed to fetch conversations: \(error)")
            return []
        }
    }

    public func generateTitle(for conversation: ChatConversation, using client: any AIClient) async {
        let messages = (conversation.messages ?? []).sorted { $0.timestamp < $1.timestamp }
        guard messages.count >= 2 else { return }

        var prompt = "Generate a short (3-5 words) title for this conversation:\n\n"
        for message in messages.prefix(4) {
            let role = message.isUser ? "User" : "Assistant"
            prompt += "\(role): \(message.content.prefix(200))...\n\n"
        }
        prompt += "Title:"

        let options = AIClientOptions(
            systemPrompt: "Generate a concise, descriptive title (3-5 words) that captures the main topic of the conversation. Do not use quotes or special characters."
        )

        do {
            let result = try await client.run(prompt: prompt, options: options, onOutput: nil)

            let cleanTitle = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")

            updateTitle(conversation, title: cleanTitle)
        } catch {
            print("Failed to generate title: \(error)")
        }
    }

    public func shouldGenerateTitle(for conversation: ChatConversation) -> Bool {
        return (conversation.messages ?? []).count >= 2 &&
               (conversation.messages ?? []).count <= 4 &&
               conversation.title == "New Conversation"
    }

    public func loadMessages(from conversation: ChatConversation) -> [ChatMessage] {
        return (conversation.messages ?? []).sorted { $0.timestamp < $1.timestamp }
    }
}
