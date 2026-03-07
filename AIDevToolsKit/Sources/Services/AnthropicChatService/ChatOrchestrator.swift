import AnthropicSDK
import Foundation
@preconcurrency import SwiftAnthropic

public actor ChatOrchestrator {
    private let apiClient: AnthropicAPIClient

    public init(apiClient: AnthropicAPIClient) {
        self.apiClient = apiClient
    }

    public func sendMessage(
        _ content: String,
        history: [MessageParameter.Message],
        tools: [MessageParameter.Tool]? = nil,
        systemPrompt: String? = nil
    ) async throws -> ChatResponse {
        let parameters = MessageBuilder.buildMessage(
            messages: history,
            tools: tools,
            systemPrompt: systemPrompt
        )

        let response = try await apiClient.sendMessage(parameters)
        let responseData = await apiClient.extractResponseData(from: response)

        if !responseData.toolCalls.isEmpty {
            let toolResults = try await processToolCalls(
                responseData.toolCalls,
                originalMessages: history,
                initialResponse: response
            )

            return ChatResponse(
                textContent: responseData.textContent,
                toolResults: toolResults
            )
        }

        return ChatResponse(textContent: responseData.textContent)
    }

    nonisolated public func streamMessage(
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
            let task = Task { [weak self] in
                guard self != nil else {
                    continuation.finish()
                    return
                }

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

    private func processToolCalls(
        _ toolCalls: [MessageResponse.Content.ToolUse],
        originalMessages: [MessageParameter.Message],
        initialResponse: MessageResponse?
    ) async throws -> [String] {
        var toolResults: [MessageParameter.Message.Content.ContentObject] = []
        var resultStrings: [String] = []

        for toolCall in toolCalls {
            resultStrings.append("Tool '\(toolCall.name)' called (no handler configured).")

            let toolResultContent = MessageBuilder.createToolResult(
                toolId: toolCall.id,
                result: "Tool execution not available"
            )
            toolResults.append(toolResultContent)
        }

        if let initialResponse {
            let followUpMessages = MessageBuilder.buildFollowUpMessages(
                originalMessages: originalMessages,
                assistantResponse: initialResponse,
                toolResults: toolResults
            )

            let followUpParams = MessageBuilder.buildMessage(
                messages: followUpMessages,
                maxTokens: 4096
            )

            let followUpResponse = try await apiClient.sendMessage(followUpParams)
            let followUpData = await apiClient.extractResponseData(from: followUpResponse)

            if !followUpData.textContent.isEmpty {
                resultStrings.append(followUpData.textContent)
            }
        }

        return resultStrings
    }
}
