import AnthropicSDK
import AnthropicChatService
import Foundation
@preconcurrency import SwiftAnthropic
import SwiftData

public struct ChatMessageUI: Identifiable, Sendable {
    public let id = UUID()
    public let content: String
    public let isUser: Bool
    public let timestamp = Date()

    public init(content: String, isUser: Bool) {
        self.content = content
        self.isUser = isUser
    }
}

@MainActor
@Observable
public final class ChatViewModel {
    // MARK: - UI State

    public var messages: [ChatMessageUI] = []
    public var isLoading = false
    public var isStreaming = false
    public var streamingMessage = ""
    public var errorMessage: String?
    public var currentConversation: ChatConversation?

    // MARK: - Dependencies

    private let apiClient: AnthropicAPIClient
    private let chatSimpleService: ChatSimpleService
    private let chatStreamingService: ChatStreamingService
    private let conversationManager: ConversationManager

    private var currentStreamTask: Task<Void, Never>?
    private var systemPrompt: String
    private var tools: [MessageParameter.Tool]?
    private var toolHandler: ToolExecutionHandler?

    // MARK: - Initialization

    public init(
        apiKey: String,
        modelContext: ModelContext,
        systemPrompt: String = MessageBuilder.defaultSystemPrompt(),
        tools: [MessageParameter.Tool]? = nil,
        toolHandler: ToolExecutionHandler? = nil
    ) {
        self.apiClient = AnthropicAPIClient(apiKey: apiKey)
        self.chatSimpleService = ChatSimpleService(apiClient: apiClient)
        self.chatStreamingService = ChatStreamingService(apiClient: apiClient)
        self.conversationManager = ConversationManager(modelContext: modelContext)
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.toolHandler = toolHandler
    }

    // MARK: - Configuration

    public func updateAPIKey(_ newKey: String) async {
        await apiClient.updateAPIKey(newKey)
    }

    public func updateSystemPrompt(_ prompt: String) {
        self.systemPrompt = prompt
    }

    public func updateTools(_ tools: [MessageParameter.Tool]?, handler: ToolExecutionHandler?) {
        self.tools = tools
        self.toolHandler = handler
    }

    // MARK: - Messaging

    public func sendMessage(_ content: String) async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        do {
            try await apiClient.validateAPIKey()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        addMessage(content, isUser: true)
        isLoading = true
        errorMessage = nil

        let apiMessages = convertToAPIMessages()

        do {
            let response = try await chatSimpleService.sendMessage(
                content,
                history: apiMessages,
                tools: tools,
                systemPrompt: systemPrompt,
                toolHandler: toolHandler
            )

            if !response.textContent.isEmpty {
                addMessage(response.textContent, isUser: false)
            }

            for result in response.toolResults {
                addMessage(result, isUser: false)
            }

            await checkAndGenerateTitle()
        } catch let error as AnthropicError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }

        isLoading = false
    }

    public func streamMessage(_ content: String) async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        do {
            try await apiClient.validateAPIKey()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        addMessage(content, isUser: true)
        isLoading = true
        isStreaming = true
        streamingMessage = ""
        errorMessage = nil

        currentStreamTask?.cancel()

        let task = Task {
            do {
                let apiMessages = convertToAPIMessages()

                let eventStream = try await chatStreamingService.streamMessage(
                    content,
                    history: apiMessages,
                    tools: tools,
                    systemPrompt: systemPrompt,
                    toolHandler: toolHandler
                )

                var fullText = ""

                for await event in eventStream {
                    if Task.isCancelled { break }

                    switch event {
                    case .text(let text):
                        streamingMessage += text
                        fullText += text

                    case .toolUse(let name, _):
                        addMessage("Using tool: \(name)", isUser: false)

                    case .toolResult(let result):
                        addMessage(result, isUser: false)

                    case .completed:
                        isStreaming = false
                        streamingMessage = ""

                        if !fullText.isEmpty {
                            addMessage(fullText, isUser: false)
                        }

                        await checkAndGenerateTitle()

                    case .error(let error):
                        isStreaming = false
                        streamingMessage = ""

                        if let anthropicError = error as? AnthropicError {
                            errorMessage = anthropicError.localizedDescription
                        } else {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            } catch {
                isStreaming = false
                streamingMessage = ""

                if error is CancellationError {
                    return
                }

                if let anthropicError = error as? AnthropicError {
                    errorMessage = anthropicError.localizedDescription
                } else {
                    errorMessage = error.localizedDescription
                }
            }

            isLoading = false
        }

        currentStreamTask = task
    }

    public func clearConversation() {
        messages.removeAll()
        errorMessage = nil
    }

    // MARK: - Conversation Management

    public func loadConversation(_ conversation: ChatConversation) {
        currentConversation = conversation
        messages.removeAll()

        let chatMessages = conversationManager.loadMessages(from: conversation)
        for message in chatMessages {
            messages.append(ChatMessageUI(
                content: message.content,
                isUser: message.isUser
            ))
        }
    }

    public func createNewConversation(title: String = "New Conversation") -> ChatConversation? {
        let conversation = conversationManager.createConversation(title: title)
        if let conversation {
            currentConversation = conversation
            messages.removeAll()
        }
        return conversation
    }

    public func updateConversationTitle(_ conversation: ChatConversation, title: String) {
        conversationManager.updateTitle(conversation, title: title)
    }

    public func deleteConversation(_ conversation: ChatConversation) {
        if currentConversation?.id == conversation.id {
            currentConversation = nil
            messages.removeAll()
        }
        conversationManager.deleteConversation(conversation)
    }

    public func fetchConversations() -> [ChatConversation] {
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

    private func convertToAPIMessages() -> [MessageParameter.Message] {
        messages.map { msg in
            MessageParameter.Message(
                role: msg.isUser ? .user : .assistant,
                content: .text(msg.content)
            )
        }
    }

    private func checkAndGenerateTitle() async {
        guard let conversation = currentConversation,
              conversationManager.shouldGenerateTitle(for: conversation) else {
            return
        }

        await conversationManager.generateTitle(for: conversation, using: apiClient)
    }
}
