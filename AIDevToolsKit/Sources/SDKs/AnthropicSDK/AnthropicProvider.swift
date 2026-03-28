import AIOutputSDK
import Foundation
@preconcurrency import SwiftAnthropic

public actor AnthropicProvider: AIClient {
    public nonisolated var name: String { "anthropic-api" }
    public nonisolated var displayName: String { "Anthropic API" }

    private let apiClient: AnthropicAPIClient
    private let storage: AnthropicSessionStorage
    private var conversations: [String: [MessageParameter.Message]] = [:]

    public init(apiClient: AnthropicAPIClient, storageDirectory: URL? = nil) {
        self.apiClient = apiClient
        self.storage = AnthropicSessionStorage(baseDirectory: storageDirectory)
    }

    public func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        let sessionId = options.sessionId ?? UUID().uuidString

        if conversations[sessionId] == nil {
            let persisted = await storage.loadPersistedMessages(sessionId: sessionId)
            if !persisted.isEmpty {
                conversations[sessionId] = persisted.map { msg in
                    MessageParameter.Message(
                        role: msg.role == "user" ? .user : .assistant,
                        content: .text(msg.content)
                    )
                }
            }
        }

        var history = conversations[sessionId] ?? []

        let userMessage = MessageParameter.Message(role: .user, content: .text(prompt))
        history.append(userMessage)

        let model: SwiftAnthropic.Model = options.model.map { .other($0) } ?? .other("claude-sonnet-4-20250514")
        let parameters = MessageParameter(
            model: model,
            messages: history,
            maxTokens: 4096,
            system: options.systemPrompt.map { .text($0) },
            metadata: nil,
            stopSequences: nil,
            stream: true,
            temperature: nil,
            topK: nil,
            topP: nil,
            tools: nil,
            toolChoice: nil,
            thinking: nil
        )

        let stream = try await apiClient.streamMessage(parameters)
        var fullResponse = ""

        for try await chunk in stream {
            if let contentBlock = chunk.contentBlock {
                if contentBlock.type == "tool_use" {
                    let name = contentBlock.name ?? ""
                    onStreamEvent?(.toolUse(name: name, detail: ""))
                }
            }
            if let delta = chunk.delta, let text = delta.text {
                fullResponse += text
                onOutput?(text)
                onStreamEvent?(.textDelta(text))
            }
        }

        let assistantMessage = MessageParameter.Message(role: .assistant, content: .text(fullResponse))
        history.append(assistantMessage)
        conversations[sessionId] = history

        let messageTuples = history.map { msg -> (role: String, content: String) in
            let role = msg.role == "user" ? "user" : "assistant"
            let content: String
            switch msg.content {
            case .text(let text):
                content = text
            case .list(let objects):
                content = objects.compactMap { obj -> String? in
                    if case .text(let text) = obj { return text }
                    return nil
                }.joined(separator: "\n")
            }
            return (role: role, content: content)
        }
        try? await storage.save(sessionId: sessionId, messages: messageTuples)

        return AIClientResult(exitCode: 0, sessionId: sessionId, stderr: "", stdout: fullResponse)
    }

    public func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        let structuredPrompt = """
            \(prompt)

            You MUST respond with valid JSON matching this schema:
            \(jsonSchema)

            Respond ONLY with the JSON object, no other text.
            """

        let result = try await run(prompt: structuredPrompt, options: options, onOutput: onOutput)

        let data = Data(result.stdout.utf8)
        let value = try JSONDecoder().decode(T.self, from: data)

        return AIStructuredResult(rawOutput: result.stdout, sessionId: result.sessionId, stderr: "", value: value)
    }

    // MARK: - Session History

    public func listSessions(workingDirectory: String) async -> [ChatSession] {
        await storage.listSessions()
    }

    public func loadSessionMessages(sessionId: String, workingDirectory: String) async -> [ChatSessionMessage] {
        await storage.loadMessages(sessionId: sessionId)
    }
}
