import Foundation
@preconcurrency import SwiftAnthropic

public actor AnthropicAPIClient {
    private var apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public func updateAPIKey(_ newKey: String) {
        self.apiKey = newKey
    }

    public func getAPIKey() -> String {
        return apiKey
    }

    public func validateAPIKey() throws {
        guard !apiKey.isEmpty else {
            throw AnthropicError.invalidAPIKey
        }
    }

    public func sendMessage(_ parameters: MessageParameter) async throws -> MessageResponse {
        try validateAPIKey()

        do {
            let service = AnthropicServiceFactory.service(apiKey: apiKey, betaHeaders: nil)
            return try await service.createMessage(parameters)
        } catch let error as SwiftAnthropic.APIError {
            throw AnthropicError.from(error)
        } catch {
            throw AnthropicError.networkError(error.localizedDescription)
        }
    }

    public func streamMessage(_ parameters: MessageParameter) async throws -> AsyncThrowingStream<MessageStreamResponse, Error> {
        try validateAPIKey()

        do {
            let service = AnthropicServiceFactory.service(apiKey: apiKey, betaHeaders: nil)
            return try await service.streamMessage(parameters)
        } catch let error as SwiftAnthropic.APIError {
            throw AnthropicError.from(error)
        } catch {
            throw AnthropicError.networkError(error.localizedDescription)
        }
    }

    public func getEventStream(parameters: MessageParameter) async throws -> AsyncStream<StreamEvent> {
        let rawStream = try await streamMessage(parameters)
        return await processStream(rawStream)
    }

    public func createSimpleMessage(
        prompt: String,
        systemPrompt: String? = nil,
        model: SwiftAnthropic.Model = .other("claude-sonnet-4-20250514"),
        maxTokens: Int = 1024,
        temperature: Double? = nil
    ) async throws -> String {
        let parameters = MessageParameter(
            model: model,
            messages: [
                MessageParameter.Message(
                    role: .user,
                    content: .text(prompt)
                )
            ],
            maxTokens: maxTokens,
            system: systemPrompt.map { .text($0) },
            metadata: nil,
            stopSequences: nil,
            stream: false,
            temperature: temperature,
            topK: nil,
            topP: nil,
            tools: nil,
            toolChoice: nil,
            thinking: nil
        )

        let response = try await sendMessage(parameters)

        var result = ""
        for content in response.content {
            if case .text(let text, _) = content {
                result += text
            }
        }

        return result
    }

    public struct MessageResponseData: Sendable {
        public let textContent: String
        public let toolCalls: [MessageResponse.Content.ToolUse]

        public init(textContent: String, toolCalls: [MessageResponse.Content.ToolUse]) {
            self.textContent = textContent
            self.toolCalls = toolCalls
        }
    }

    public func extractResponseData(from response: MessageResponse) -> MessageResponseData {
        var textContent = ""
        var toolCalls: [MessageResponse.Content.ToolUse] = []

        for content in response.content {
            switch content {
            case .text(let text, _):
                textContent += text
            case .toolUse(let toolUse):
                toolCalls.append(toolUse)
            default:
                break
            }
        }

        return MessageResponseData(textContent: textContent, toolCalls: toolCalls)
    }

    public enum StreamEvent: Sendable {
        case text(String)
        case toolUse(name: String, id: String)
        case toolInputDelta(String)
        case contentBlock(MessageStreamResponse.ContentBlock)
        case message(MessageResponse)
        case error(Error)
    }

    public func processStream(_ stream: AsyncThrowingStream<MessageStreamResponse, Error>) -> AsyncStream<StreamEvent> {
        AsyncStream<StreamEvent> { continuation in
            let task = Task { @Sendable in
                do {
                    var fullResponse = ""

                    for try await chunk in stream {
                        if let contentBlock = chunk.contentBlock {
                            if contentBlock.type == "tool_use" {
                                continuation.yield(.toolUse(name: contentBlock.name ?? "", id: contentBlock.id ?? ""))
                            }
                            continuation.yield(.contentBlock(contentBlock))
                        }

                        if let delta = chunk.delta {
                            if let text = delta.text {
                                fullResponse += text
                                continuation.yield(.text(text))
                            }
                            if let partialJson = delta.partialJson {
                                continuation.yield(.toolInputDelta(partialJson))
                            }
                        }

                        if let message = chunk.message {
                            continuation.yield(.message(message))
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
