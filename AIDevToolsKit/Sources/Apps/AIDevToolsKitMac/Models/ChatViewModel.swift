import AIOutputSDK
import AnthropicChatService
import Foundation
import SwiftData

struct ChatMessageUI: Identifiable, Sendable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp = Date()
}

@MainActor
@Observable
final class ChatViewModel {
    // MARK: - UI State

    var messages: [ChatMessageUI] = []
    var isLoading = false
    var isStreaming = false
    var streamingMessage = ""
    var errorMessage: String?
    var currentConversation: ChatConversation?

    // MARK: - Dependencies

    private let client: any AIClient
    private let conversationManager: ConversationManager

    private var currentStreamTask: Task<Void, Never>?
    private var sessionId: String?
    private var systemPrompt: String

    // MARK: - Initialization

    init(
        client: any AIClient,
        modelContext: ModelContext,
        systemPrompt: String = "You are a helpful AI assistant."
    ) {
        self.client = client
        self.conversationManager = ConversationManager(modelContext: modelContext)
        self.systemPrompt = systemPrompt
    }

    // MARK: - Configuration

    func updateSystemPrompt(_ prompt: String) {
        self.systemPrompt = prompt
    }

    // MARK: - Messaging

    func sendMessage(_ content: String) async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        addMessage(content, isUser: true)
        isLoading = true
        errorMessage = nil

        let options = AIClientOptions(
            sessionId: sessionId,
            systemPrompt: systemPrompt
        )

        do {
            let result = try await client.run(
                prompt: content,
                options: options,
                onOutput: nil
            )

            sessionId = result.sessionId ?? sessionId

            if !result.stdout.isEmpty {
                addMessage(result.stdout, isUser: false)
            }

            await checkAndGenerateTitle()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func streamMessage(_ content: String) async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        addMessage(content, isUser: true)
        isLoading = true
        isStreaming = true
        streamingMessage = ""
        errorMessage = nil

        currentStreamTask?.cancel()

        let task = Task {
            let options = AIClientOptions(
                sessionId: sessionId,
                systemPrompt: systemPrompt
            )

            do {
                let result = try await client.run(
                    prompt: content,
                    options: options,
                    onOutput: { @Sendable [weak self] chunk in
                        Task { @MainActor in
                            self?.streamingMessage += chunk
                        }
                    }
                )

                sessionId = result.sessionId ?? sessionId
                isStreaming = false
                streamingMessage = ""

                if !result.stdout.isEmpty {
                    addMessage(result.stdout, isUser: false)
                }

                await checkAndGenerateTitle()
            } catch {
                isStreaming = false
                streamingMessage = ""

                if error is CancellationError { return }
                errorMessage = error.localizedDescription
            }

            isLoading = false
        }

        currentStreamTask = task
    }

    func clearConversation() {
        messages.removeAll()
        sessionId = nil
        errorMessage = nil
    }

    // MARK: - Conversation Management

    func loadConversation(_ conversation: ChatConversation) {
        currentConversation = conversation
        sessionId = nil
        messages.removeAll()

        let chatMessages = conversationManager.loadMessages(from: conversation)
        for message in chatMessages {
            messages.append(ChatMessageUI(
                content: message.content,
                isUser: message.isUser
            ))
        }
    }

    func createNewConversation(title: String = "New Conversation") -> ChatConversation? {
        let conversation = conversationManager.createConversation(title: title)
        if let conversation {
            currentConversation = conversation
            sessionId = nil
            messages.removeAll()
        }
        return conversation
    }

    func updateConversationTitle(_ conversation: ChatConversation, title: String) {
        conversationManager.updateTitle(conversation, title: title)
    }

    func deleteConversation(_ conversation: ChatConversation) {
        if currentConversation?.id == conversation.id {
            currentConversation = nil
            messages.removeAll()
        }
        conversationManager.deleteConversation(conversation)
    }

    func fetchConversations() -> [ChatConversation] {
        return conversationManager.fetchConversations()
    }

    // MARK: - Private Methods

    private func addMessage(_ content: String, isUser: Bool) {
        let message = ChatMessageUI(content: content, isUser: isUser)
        messages.append(message)

        if let conversation = currentConversation {
            conversationManager.saveMessage(to: conversation, content: content, isUser: isUser)
        }
    }

    private func checkAndGenerateTitle() async {
        guard let conversation = currentConversation,
              conversationManager.shouldGenerateTitle(for: conversation) else {
            return
        }

        await conversationManager.generateTitle(for: conversation, using: client)
    }
}
