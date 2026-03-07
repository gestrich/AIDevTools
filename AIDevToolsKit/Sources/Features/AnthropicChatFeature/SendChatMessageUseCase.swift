import AnthropicSDK
import AnthropicChatService
import Foundation
@preconcurrency import SwiftAnthropic

public struct SendChatMessageUseCase: Sendable {

    public struct Options: Sendable {
        public let message: String
        public let apiKey: String
        public let systemPrompt: String?
        public let streaming: Bool

        public init(
            message: String,
            apiKey: String,
            systemPrompt: String? = nil,
            streaming: Bool = true
        ) {
            self.message = message
            self.apiKey = apiKey
            self.systemPrompt = systemPrompt
            self.streaming = streaming
        }
    }

    public enum Progress: Sendable {
        case textDelta(String)
        case toolUse(name: String)
        case completed(fullText: String)
    }

    public init() {}

    public func run(
        _ options: Options,
        history: [MessageParameter.Message] = [],
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> String {
        let apiClient = AnthropicAPIClient(apiKey: options.apiKey)
        let systemPrompt = options.systemPrompt ?? MessageBuilder.defaultSystemPrompt()

        var allMessages = history
        allMessages.append(MessageParameter.Message(role: .user, content: .text(options.message)))

        if options.streaming {
            return try await runStreaming(
                apiClient: apiClient,
                messages: allMessages,
                systemPrompt: systemPrompt,
                onProgress: onProgress
            )
        } else {
            return try await runSimple(
                apiClient: apiClient,
                messages: allMessages,
                systemPrompt: systemPrompt
            )
        }
    }

    // MARK: - Private

    private func runStreaming(
        apiClient: AnthropicAPIClient,
        messages: [MessageParameter.Message],
        systemPrompt: String,
        onProgress: (@Sendable (Progress) -> Void)?
    ) async throws -> String {
        let parameters = MessageBuilder.buildMessage(
            messages: messages,
            systemPrompt: systemPrompt,
            stream: true
        )

        let eventStream = try await apiClient.getEventStream(parameters: parameters)
        var fullText = ""

        for await event in eventStream {
            switch event {
            case .text(let text):
                fullText += text
                onProgress?(.textDelta(text))
            case .toolUse(let name, _):
                onProgress?(.toolUse(name: name))
            case .error(let error):
                throw error
            default:
                break
            }
        }

        onProgress?(.completed(fullText: fullText))
        return fullText
    }

    private func runSimple(
        apiClient: AnthropicAPIClient,
        messages: [MessageParameter.Message],
        systemPrompt: String
    ) async throws -> String {
        let parameters = MessageBuilder.buildMessage(
            messages: messages,
            systemPrompt: systemPrompt
        )

        let response = try await apiClient.sendMessage(parameters)
        let data = await apiClient.extractResponseData(from: response)
        return data.textContent
    }
}
