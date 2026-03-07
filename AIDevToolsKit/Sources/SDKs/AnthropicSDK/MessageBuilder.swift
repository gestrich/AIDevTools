import Foundation
@preconcurrency import SwiftAnthropic

public struct MessageBuilder {
    public static func defaultSystemPrompt() -> String {
        "You are a helpful AI assistant."
    }

    public static func buildMessage(
        messages: [MessageParameter.Message],
        model: SwiftAnthropic.Model = .other("claude-sonnet-4-20250514"),
        tools: [MessageParameter.Tool]? = nil,
        systemPrompt: String? = nil,
        maxTokens: Int = 4096,
        stream: Bool = false,
        temperature: Double? = nil,
        toolChoice: MessageParameter.ToolChoice? = nil
    ) -> MessageParameter {
        MessageParameter(
            model: model,
            messages: messages,
            maxTokens: maxTokens,
            system: systemPrompt.map { .text($0) },
            metadata: nil,
            stopSequences: nil,
            stream: stream,
            temperature: temperature,
            topK: nil,
            topP: nil,
            tools: tools,
            toolChoice: toolChoice,
            thinking: nil
        )
    }

    public static func buildFollowUpMessages(
        originalMessages: [MessageParameter.Message],
        assistantResponse: MessageResponse,
        toolResults: [MessageParameter.Message.Content.ContentObject]
    ) -> [MessageParameter.Message] {
        var messages = originalMessages

        let assistantContent = assistantResponse.content.compactMap { content -> MessageParameter.Message.Content.ContentObject? in
            switch content {
            case .text(let text, _):
                return .text(text)
            case .toolUse(let toolUse):
                return .toolUse(toolUse.id, toolUse.name, toolUse.input)
            default:
                return nil
            }
        }

        messages.append(MessageParameter.Message(role: .assistant, content: .list(assistantContent)))
        messages.append(MessageParameter.Message(role: .user, content: .list(toolResults)))

        return messages
    }

    public static func createToolResult(
        toolId: String,
        result: String,
        isError: Bool = false
    ) -> MessageParameter.Message.Content.ContentObject {
        .toolResult(toolId, result, isError, nil)
    }
}
