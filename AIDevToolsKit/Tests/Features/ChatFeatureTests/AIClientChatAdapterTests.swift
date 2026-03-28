import AIOutputSDK
import Foundation
import Testing
@testable import ChatFeature

// MARK: - Mock AIClient

private final class MockAIClient: AIClient, @unchecked Sendable {
    let displayName: String
    let name: String

    var lastPrompt: String?
    var lastOptions: AIClientOptions?
    var stubbedResult: AIClientResult
    var streamEventsToEmit: [AIStreamEvent] = []
    var runCallCount = 0

    init(
        name: String = "mock",
        displayName: String = "Mock Provider",
        stubbedResult: AIClientResult = AIClientResult(exitCode: 0, sessionId: "session-1", stderr: "", stdout: "Hello from mock")
    ) {
        self.displayName = displayName
        self.name = name
        self.stubbedResult = stubbedResult
    }

    func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        runCallCount += 1
        lastPrompt = prompt
        lastOptions = options
        for event in streamEventsToEmit {
            onStreamEvent?(event)
        }
        return stubbedResult
    }

    func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        fatalError("Not used in adapter tests")
    }
}

// MARK: - Mock SessionListable AIClient

private final class MockSessionClient: AIClient, SessionListable, @unchecked Sendable {
    let displayName = "Session Mock"
    let name = "session-mock"

    var stubbedSessions: [ChatSession] = []
    var stubbedMessages: [ChatSessionMessage] = []
    var stubbedDetails: SessionDetails?
    var listSessionsCalled = false
    var loadMessagesCalled = false
    var lastLoadSessionId: String?

    func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        AIClientResult(exitCode: 0, sessionId: "s1", stderr: "", stdout: "response")
    }

    func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        fatalError("Not used in adapter tests")
    }

    func listSessions(workingDirectory: String) async -> [ChatSession] {
        listSessionsCalled = true
        return stubbedSessions
    }

    func loadSessionMessages(sessionId: String, workingDirectory: String) async -> [ChatSessionMessage] {
        loadMessagesCalled = true
        lastLoadSessionId = sessionId
        return stubbedMessages
    }

    func getSessionDetails(sessionId: String, summary: String, lastModified: Date, workingDirectory: String) -> SessionDetails? {
        stubbedDetails
    }
}

// MARK: - Properties Tests

struct AIClientChatAdapterPropertyTests {

    @Test func displaysClientName() {
        let client = MockAIClient(name: "anthropic", displayName: "Claude API")
        let adapter = AIClientChatAdapter(client: client)
        #expect(adapter.displayName == "Claude API")
        #expect(adapter.name == "anthropic")
    }

    @Test func supportsSessionHistoryWhenSessionListable() {
        let client = MockSessionClient()
        let adapter = AIClientChatAdapter(client: client)
        #expect(adapter.supportsSessionHistory == true)
    }

    @Test func doesNotSupportSessionHistoryWithPlainClient() {
        let client = MockAIClient()
        let adapter = AIClientChatAdapter(client: client)
        #expect(adapter.supportsSessionHistory == false)
    }
}

// MARK: - Factory Tests

struct AIClientChatAdapterFactoryTests {

    @Test func makeDetectsSessionListable() {
        let client = MockSessionClient()
        let adapter = AIClientChatAdapter.make(from: client)
        #expect(adapter.supportsSessionHistory == true)
    }

    @Test func makeHandlesPlainClient() {
        let client = MockAIClient()
        let adapter = AIClientChatAdapter.make(from: client)
        #expect(adapter.supportsSessionHistory == false)
    }
}

// MARK: - sendMessage Tests

struct AIClientChatAdapterSendMessageTests {

    @Test func forwardsMessageToClient() async throws {
        let client = MockAIClient()
        let adapter = AIClientChatAdapter(client: client)
        let options = ChatProviderOptions(
            model: "claude-sonnet-4-20250514",
            sessionId: "s1",
            systemPrompt: "Be helpful.",
            workingDirectory: "/tmp"
        )

        _ = try await adapter.sendMessage("Hello", images: [], options: options, onStreamEvent: nil)

        #expect(client.lastPrompt == "Hello")
        #expect(client.lastOptions?.model == "claude-sonnet-4-20250514")
        #expect(client.lastOptions?.sessionId == "s1")
        #expect(client.lastOptions?.systemPrompt == "Be helpful.")
        #expect(client.lastOptions?.workingDirectory == "/tmp")
    }

    @Test func returnsContentAndSessionId() async throws {
        let client = MockAIClient(
            stubbedResult: AIClientResult(exitCode: 0, sessionId: "new-session", stderr: "", stdout: "Response text")
        )
        let adapter = AIClientChatAdapter(client: client)

        let result = try await adapter.sendMessage("Test", images: [], options: ChatProviderOptions(), onStreamEvent: nil)

        #expect(result.content == "Response text")
        #expect(result.sessionId == "new-session")
    }

    @Test func returnsNilSessionIdWhenClientOmitsIt() async throws {
        let client = MockAIClient(
            stubbedResult: AIClientResult(exitCode: 0, sessionId: nil, stderr: "", stdout: "Hi")
        )
        let adapter = AIClientChatAdapter(client: client)

        let result = try await adapter.sendMessage("Test", images: [], options: ChatProviderOptions(), onStreamEvent: nil)

        #expect(result.sessionId == nil)
    }

    @Test func forwardsStreamEvents() async throws {
        let client = MockAIClient()
        client.streamEventsToEmit = [
            .textDelta("Hello "),
            .textDelta("world"),
            .thinking("Let me think..."),
        ]
        let adapter = AIClientChatAdapter(client: client)
        var received: [AIStreamEvent] = []

        _ = try await adapter.sendMessage("Test", images: [], options: ChatProviderOptions()) { event in
            received.append(event)
        }

        #expect(received.count == 3)
    }

    @Test func forwardsDangerouslySkipPermissions() async throws {
        let client = MockAIClient()
        let adapter = AIClientChatAdapter(client: client)
        let options = ChatProviderOptions(dangerouslySkipPermissions: true)

        _ = try await adapter.sendMessage("Test", images: [], options: options, onStreamEvent: nil)

        #expect(client.lastOptions?.dangerouslySkipPermissions == true)
    }

    @Test func imageAttachmentAugmentsPrompt() async throws {
        let pngBase64 = Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()
        let image = ImageAttachment(base64Data: pngBase64, mediaType: "image/png")
        let client = MockAIClient()
        let adapter = AIClientChatAdapter(client: client)

        _ = try await adapter.sendMessage("Describe this", images: [image], options: ChatProviderOptions(), onStreamEvent: nil)

        let prompt = try #require(client.lastPrompt)
        #expect(prompt.contains("Describe this"))
        #expect(prompt.contains("1 image(s)"))
        #expect(prompt.contains("Image 1:"))
    }

    @Test func plainMessageWithoutImagesIsUnmodified() async throws {
        let client = MockAIClient()
        let adapter = AIClientChatAdapter(client: client)

        _ = try await adapter.sendMessage("Just text", images: [], options: ChatProviderOptions(), onStreamEvent: nil)

        #expect(client.lastPrompt == "Just text")
    }
}

// MARK: - Session Delegation Tests

struct AIClientChatAdapterSessionTests {

    @Test func listSessionsDelegatesToSessionListable() async {
        let client = MockSessionClient()
        client.stubbedSessions = [
            ChatSession(id: "s1", lastModified: Date(), summary: "First session"),
            ChatSession(id: "s2", lastModified: Date(), summary: "Second session"),
        ]
        let adapter = AIClientChatAdapter(client: client)

        let sessions = await adapter.listSessions(workingDirectory: "/tmp")

        #expect(sessions.count == 2)
        #expect(sessions[0].id == "s1")
        #expect(sessions[1].id == "s2")
        #expect(client.listSessionsCalled == true)
    }

    @Test func listSessionsReturnsEmptyForPlainClient() async {
        let client = MockAIClient()
        let adapter = AIClientChatAdapter(client: client)

        let sessions = await adapter.listSessions(workingDirectory: "/tmp")

        #expect(sessions.isEmpty)
    }

    @Test func loadSessionMessagesDelegatesToSessionListable() async {
        let client = MockSessionClient()
        client.stubbedMessages = [
            ChatSessionMessage(content: "Hello", role: .user),
            ChatSessionMessage(content: "Hi there!", role: .assistant),
        ]
        let adapter = AIClientChatAdapter(client: client)

        let messages = await adapter.loadSessionMessages(sessionId: "s1", workingDirectory: "/tmp")

        #expect(messages.count == 2)
        #expect(messages[0].content == "Hello")
        #expect(messages[1].role == .assistant)
        #expect(client.lastLoadSessionId == "s1")
    }

    @Test func loadSessionMessagesReturnsEmptyForPlainClient() async {
        let client = MockAIClient()
        let adapter = AIClientChatAdapter(client: client)

        let messages = await adapter.loadSessionMessages(sessionId: "s1", workingDirectory: "/tmp")

        #expect(messages.isEmpty)
    }

    @Test func getSessionDetailsDelegatesToSessionListable() {
        let client = MockSessionClient()
        let session = ChatSession(id: "s1", lastModified: Date(), summary: "Test")
        client.stubbedDetails = SessionDetails(
            cwd: "/project",
            gitBranch: "main",
            rawJsonLines: ["{}"],
            session: session
        )
        let adapter = AIClientChatAdapter(client: client)

        let details = adapter.getSessionDetails(
            sessionId: "s1",
            summary: "Test",
            lastModified: Date(),
            workingDirectory: "/project"
        )

        #expect(details?.cwd == "/project")
        #expect(details?.gitBranch == "main")
    }

    @Test func getSessionDetailsReturnsNilForPlainClient() {
        let client = MockAIClient()
        let adapter = AIClientChatAdapter(client: client)

        let details = adapter.getSessionDetails(
            sessionId: "s1",
            summary: "Test",
            lastModified: Date(),
            workingDirectory: "/tmp"
        )

        #expect(details == nil)
    }
}
