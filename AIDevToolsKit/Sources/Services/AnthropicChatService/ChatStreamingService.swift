import AnthropicSDK
import Foundation
@preconcurrency import SwiftAnthropic

@MainActor
public final class ChatStreamingService {
    private let apiClient: AnthropicAPIClient

    public init(apiClient: AnthropicAPIClient) {
        self.apiClient = apiClient
    }

    public func streamMessage(
        _ content: String,
        history: [MessageParameter.Message],
        tools: [MessageParameter.Tool]? = nil,
        systemPrompt: String? = nil,
        toolHandler: ToolExecutionHandler? = nil
    ) async throws -> AsyncStream<ChatEvent> {
        let parameters = MessageBuilder.buildMessage(
            messages: history,
            tools: tools,
            systemPrompt: systemPrompt,
            stream: true
        )

        let eventStream = try await apiClient.getEventStream(parameters: parameters)

        return AsyncStream<ChatEvent> { continuation in
            let task = Task {
                var fullText = ""
                var toolCalls: [MessageResponse.Content.ToolUse] = []

                for await event in eventStream {
                    switch event {
                    case .text(let text):
                        fullText += text
                        continuation.yield(.text(text))

                    case .toolUse(let name, let id):
                        continuation.yield(.toolUse(name: name, id: id))

                    case .message(let message):
                        for content in message.content {
                            if case .toolUse(let toolUse) = content {
                                toolCalls.append(toolUse)
                            }
                        }

                    case .error(let error):
                        continuation.yield(.error(error))
                        continuation.finish()
                        return

                    default:
                        break
                    }
                }

                if !toolCalls.isEmpty {
                    if let toolHandler {
                        for toolCall in toolCalls {
                            do {
                                let result = try await toolHandler(toolCall)
                                continuation.yield(.toolResult(result))
                            } catch {
                                continuation.yield(.toolResult("Error executing tool '\(toolCall.name)': \(error.localizedDescription)"))
                            }
                        }
                    } else {
                        for toolCall in toolCalls {
                            continuation.yield(.toolResult("Tool '\(toolCall.name)' detected but no handler provided"))
                        }
                    }
                }

                continuation.yield(.completed(ChatResponse(textContent: fullText)))
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
