import AnthropicSDK
import Foundation
@preconcurrency import SwiftAnthropic

@MainActor
public final class ChatSimpleService {
    private let apiClient: AnthropicAPIClient

    public init(apiClient: AnthropicAPIClient) {
        self.apiClient = apiClient
    }

    public func sendMessage(
        _ content: String,
        history: [MessageParameter.Message],
        tools: [MessageParameter.Tool]? = nil,
        systemPrompt: String? = nil,
        toolHandler: ToolExecutionHandler? = nil
    ) async throws -> ChatResponse {
        let parameters = MessageBuilder.buildMessage(
            messages: history,
            tools: tools,
            systemPrompt: systemPrompt
        )

        let response = try await apiClient.sendMessage(parameters)
        let responseData = await apiClient.extractResponseData(from: response)

        if !responseData.toolCalls.isEmpty {
            var toolResults: [String] = []

            for toolCall in responseData.toolCalls {
                if let toolHandler {
                    do {
                        let result = try await toolHandler(toolCall)
                        toolResults.append(result)
                    } catch {
                        toolResults.append("Error: \(error.localizedDescription)")
                    }
                } else {
                    toolResults.append("Tool '\(toolCall.name)' called (no handler configured).")
                }
            }

            return ChatResponse(
                textContent: responseData.textContent,
                toolResults: toolResults
            )
        }

        return ChatResponse(textContent: responseData.textContent)
    }
}
