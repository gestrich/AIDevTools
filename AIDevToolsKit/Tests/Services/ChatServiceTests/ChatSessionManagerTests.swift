import Foundation
import Testing
@testable import AIOutputSDK
@testable import ChatService

@Suite struct ChatSessionManagerTests {

    // MARK: - Conversation management

    @Test func createConversationReturnsNewConversation() async {
        let manager = ChatSessionManager(client: MockAIClient())
        let conversation = await manager.createConversation(title: "Test")

        #expect(conversation.title == "Test")
        #expect(conversation.messages.isEmpty)
        #expect(conversation.sessionId == nil)
    }

    @Test func conversationByIdReturnsCreatedConversation() async {
        let manager = ChatSessionManager(client: MockAIClient())
        let conversation = await manager.createConversation()

        let fetched = await manager.conversation(id: conversation.id)
        #expect(fetched?.id == conversation.id)
    }

    @Test func conversationByIdReturnsNilForUnknown() async {
        let manager = ChatSessionManager(client: MockAIClient())

        let fetched = await manager.conversation(id: UUID())
        #expect(fetched == nil)
    }

    @Test func allConversationsReturnsSortedByLastModified() async {
        let manager = ChatSessionManager(client: MockAIClient())
        let first = await manager.createConversation(title: "First")
        let second = await manager.createConversation(title: "Second")

        let all = await manager.allConversations()
        #expect(all.count == 2)
        #expect(all[0].id == second.id)
        #expect(all[1].id == first.id)
    }

    // MARK: - Sending messages

    @Test func sendAppendsUserAndAssistantMessages() async throws {
        let client = MockAIClient(
            runResult: AIClientResult(exitCode: 0, sessionId: "session-1", stderr: "", stdout: "Hello back!")
        )
        let manager = ChatSessionManager(client: client)
        let conversation = await manager.createConversation()

        let events = EventCollector()
        try await manager.send(
            message: "Hello",
            conversationId: conversation.id,
            onEvent: { events.append($0) }
        )

        let updated = await manager.conversation(id: conversation.id)!
        #expect(updated.messages.count == 2)
        #expect(updated.messages[0].isUser == true)
        #expect(updated.messages[0].content == "Hello")
        #expect(updated.messages[1].isUser == false)
        #expect(updated.messages[1].content == "Hello back!")
    }

    @Test func sendUpdatesSessionIdFromResult() async throws {
        let client = MockAIClient(
            runResult: AIClientResult(exitCode: 0, sessionId: "session-abc", stderr: "", stdout: "response")
        )
        let manager = ChatSessionManager(client: client)
        let conversation = await manager.createConversation()

        try await manager.send(
            message: "Hi",
            conversationId: conversation.id,
            onEvent: { _ in }
        )

        let updated = await manager.conversation(id: conversation.id)!
        #expect(updated.sessionId == "session-abc")
    }

    @Test func secondMessagePassesSessionIdFromFirstResponse() async throws {
        let client = MockAIClient(
            runResult: AIClientResult(exitCode: 0, sessionId: "session-1", stderr: "", stdout: "first response")
        )
        let manager = ChatSessionManager(client: client)
        let conversation = await manager.createConversation()

        try await manager.send(
            message: "First",
            conversationId: conversation.id,
            onEvent: { _ in }
        )

        try await manager.send(
            message: "Second",
            conversationId: conversation.id,
            onEvent: { _ in }
        )

        #expect(client.lastRunOptions?.sessionId == "session-1")
    }

    @Test func sendEmitsStreamingEventsInOrder() async throws {
        let client = MockAIClient(
            runResult: AIClientResult(exitCode: 0, stderr: "", stdout: "full response"),
            onRunOutput: ["chunk1", "chunk2"]
        )
        let manager = ChatSessionManager(client: client)
        let conversation = await manager.createConversation()

        let events = EventCollector()
        try await manager.send(
            message: "Hi",
            conversationId: conversation.id,
            onEvent: { events.append($0) }
        )

        let descriptions = events.all.map { $0.description }
        #expect(descriptions.contains("textDelta(chunk1)"))
        #expect(descriptions.contains("textDelta(chunk2)"))
        #expect(descriptions.last == "completed(full response)")
    }

    @Test func sendToUnknownConversationThrows() async {
        let manager = ChatSessionManager(client: MockAIClient())

        await #expect(throws: ChatSessionError.self) {
            try await manager.send(
                message: "Hi",
                conversationId: UUID(),
                onEvent: { _ in }
            )
        }
    }

    @Test func sendPropagatesClientError() async {
        let client = MockAIClient(error: MockError.testError)
        let manager = ChatSessionManager(client: client)
        let conversation = await manager.createConversation()

        await #expect(throws: MockError.self) {
            try await manager.send(
                message: "Hi",
                conversationId: conversation.id,
                onEvent: { _ in }
            )
        }
    }
}

// MARK: - Test doubles

private enum MockError: Error {
    case testError
}

private final class MockAIClient: AIClient, @unchecked Sendable {
    let name = "mock"
    let displayName = "Mock"

    let error: Error?
    let onRunOutput: [String]
    let runResult: AIClientResult?
    var lastRunOptions: AIClientOptions?

    init(
        error: Error? = nil,
        runResult: AIClientResult? = nil,
        onRunOutput: [String] = []
    ) {
        self.error = error
        self.onRunOutput = onRunOutput
        self.runResult = runResult
    }

    func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        lastRunOptions = options
        if let error { throw error }
        for chunk in onRunOutput {
            onOutput?(chunk)
        }
        return runResult ?? AIClientResult(exitCode: 0, stderr: "", stdout: "")
    }

    func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        fatalError("Not used in ChatSessionManager tests")
    }
}

private final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [ChatStreamEvent] = []

    func append(_ event: ChatStreamEvent) {
        lock.lock()
        defer { lock.unlock() }
        _events.append(event)
    }

    var all: [ChatStreamEvent] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }
}

extension ChatStreamEvent: CustomStringConvertible {
    public var description: String {
        switch self {
        case .completed(let text): "completed(\(text))"
        case .error(let error): "error(\(error))"
        case .textDelta(let delta): "textDelta(\(delta))"
        }
    }
}
