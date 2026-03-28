import AIOutputSDK
import Foundation
import Testing
@testable import ChatFeature

// Imported from the Mac app target — we need the ChatModel which lives there.
// Since ChatModel is in AIDevToolsKitMac (App layer), we test the ChatProvider
// integration through the adapter and protocol. The ChatModel view model
// cannot be directly tested from ChatFeatureTests without importing the app target.
// Instead, we validate the full provider flow through integration-style tests
// on the adapter and protocol surface.

// MARK: - Mock Provider for Integration Tests

private actor IntegrationMockProvider: ChatProvider {
    let displayName: String
    let name: String
    let supportsSessionHistory: Bool

    var sendMessageCallCount = 0
    var lastMessage: String?
    var lastOptions: ChatProviderOptions?
    var lastImages: [ImageAttachment] = []
    var stubbedResult: ChatProviderResult
    var stubbedError: (any Error)?
    var streamEventsToEmit: [AIStreamEvent] = []
    var stubbedSessions: [ChatSession] = []
    var stubbedSessionMessages: [ChatSessionMessage] = []

    init(
        name: String = "mock",
        displayName: String = "Mock",
        supportsSessionHistory: Bool = false,
        stubbedResult: ChatProviderResult = ChatProviderResult(content: "Response", sessionId: "s1")
    ) {
        self.displayName = displayName
        self.name = name
        self.supportsSessionHistory = supportsSessionHistory
        self.stubbedResult = stubbedResult
    }

    func sendMessage(
        _ message: String,
        images: [ImageAttachment],
        options: ChatProviderOptions,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> ChatProviderResult {
        sendMessageCallCount += 1
        lastMessage = message
        lastOptions = options
        lastImages = images
        for event in streamEventsToEmit {
            onStreamEvent?(event)
        }
        if let error = stubbedError {
            throw error
        }
        return stubbedResult
    }

    func listSessions(workingDirectory: String) async -> [ChatSession] {
        stubbedSessions
    }

    func loadSessionMessages(sessionId: String, workingDirectory: String) async -> [ChatSessionMessage] {
        stubbedSessionMessages
    }

    func cancel() async {}
}

// MARK: - Full Send/Receive Flow Tests

struct ChatProviderIntegrationTests {

    @Test func sendMessageAndReceiveResponse() async throws {
        let provider = IntegrationMockProvider(
            stubbedResult: ChatProviderResult(content: "Hello!", sessionId: "session-abc")
        )
        let options = ChatProviderOptions(workingDirectory: "/tmp")

        let result = try await provider.sendMessage("Hi", images: [], options: options, onStreamEvent: nil)

        #expect(result.content == "Hello!")
        #expect(result.sessionId == "session-abc")
        #expect(await provider.sendMessageCallCount == 1)
        #expect(await provider.lastMessage == "Hi")
    }

    @Test func streamingEventsAreDelivered() async throws {
        let provider = IntegrationMockProvider()
        await provider.setStreamEvents([
            .textDelta("Hello "),
            .textDelta("world!"),
            .thinking("Reasoning step"),
            .toolUse(name: "Read", detail: "file.swift"),
            .toolResult(name: "Read", summary: "contents", isError: false),
            .metrics(duration: 1.5, cost: 0.02, turns: 1),
        ])
        var receivedEvents: [AIStreamEvent] = []

        _ = try await provider.sendMessage("Test", images: [], options: ChatProviderOptions()) { event in
            receivedEvents.append(event)
        }

        #expect(receivedEvents.count == 6)
    }

    @Test func sessionPersistenceAcrossMessages() async throws {
        let provider = IntegrationMockProvider(
            stubbedResult: ChatProviderResult(content: "First", sessionId: "session-1")
        )

        let result1 = try await provider.sendMessage("First message", images: [], options: ChatProviderOptions(), onStreamEvent: nil)
        #expect(result1.sessionId == "session-1")

        let options2 = ChatProviderOptions(sessionId: result1.sessionId)
        let result2 = try await provider.sendMessage("Second message", images: [], options: options2, onStreamEvent: nil)

        #expect(await provider.lastOptions?.sessionId == "session-1")
        #expect(result2.sessionId == "session-1")
        #expect(await provider.sendMessageCallCount == 2)
    }

    @Test func imageAttachmentsAreForwarded() async throws {
        let provider = IntegrationMockProvider()
        let image = ImageAttachment(base64Data: "abc123", mediaType: "image/png")

        _ = try await provider.sendMessage("Analyze image", images: [image], options: ChatProviderOptions(), onStreamEvent: nil)

        let images = await provider.lastImages
        #expect(images.count == 1)
        #expect(images[0].base64Data == "abc123")
        #expect(images[0].mediaType == "image/png")
    }

    @Test func multipleImageAttachments() async throws {
        let provider = IntegrationMockProvider()
        let images = [
            ImageAttachment(base64Data: "img1", mediaType: "image/png"),
            ImageAttachment(base64Data: "img2", mediaType: "image/jpeg"),
            ImageAttachment(base64Data: "img3", mediaType: "image/png"),
        ]

        _ = try await provider.sendMessage("Compare images", images: images, options: ChatProviderOptions(), onStreamEvent: nil)

        #expect(await provider.lastImages.count == 3)
    }
}

// MARK: - Session History Tests

struct ChatProviderSessionHistoryTests {

    @Test func listSessionsReturnsHistory() async {
        let provider = IntegrationMockProvider(supportsSessionHistory: true)
        let now = Date()
        await provider.setSessions([
            ChatSession(id: "s1", lastModified: now, summary: "First"),
            ChatSession(id: "s2", lastModified: now.addingTimeInterval(-3600), summary: "Second"),
        ])

        let sessions = await provider.listSessions(workingDirectory: "/project")

        #expect(sessions.count == 2)
        #expect(sessions[0].id == "s1")
        #expect(sessions[0].summary == "First")
        #expect(sessions[1].id == "s2")
    }

    @Test func loadSessionMessagesReturnsConversation() async {
        let provider = IntegrationMockProvider(supportsSessionHistory: true)
        await provider.setSessionMessages([
            ChatSessionMessage(content: "What is 2+2?", role: .user),
            ChatSessionMessage(content: "4", role: .assistant),
            ChatSessionMessage(content: "And 3+3?", role: .user),
            ChatSessionMessage(content: "6", role: .assistant),
        ])

        let messages = await provider.loadSessionMessages(sessionId: "s1", workingDirectory: "/project")

        #expect(messages.count == 4)
        #expect(messages[0].role == .user)
        #expect(messages[1].role == .assistant)
        #expect(messages[1].content == "4")
    }

    @Test func providerWithoutSessionHistoryReturnsEmpty() async {
        let provider = IntegrationMockProvider(supportsSessionHistory: false)
        #expect(provider.supportsSessionHistory == false)

        // Default protocol extensions return empty
        let basicProvider = BasicMockProvider()
        let sessions = await basicProvider.listSessions(workingDirectory: "/tmp")
        let messages = await basicProvider.loadSessionMessages(sessionId: "s1", workingDirectory: "/tmp")

        #expect(sessions.isEmpty)
        #expect(messages.isEmpty)
    }
}

// MARK: - Provider Switching Tests

struct ChatProviderSwitchingTests {

    @Test func differentProvidersReturnDifferentResults() async throws {
        let apiProvider = IntegrationMockProvider(
            name: "anthropic",
            displayName: "Claude API",
            stubbedResult: ChatProviderResult(content: "API response", sessionId: nil)
        )
        let cliProvider = IntegrationMockProvider(
            name: "claude-cli",
            displayName: "Claude Code",
            supportsSessionHistory: true,
            stubbedResult: ChatProviderResult(content: "CLI response", sessionId: "cli-session")
        )

        let apiResult = try await apiProvider.sendMessage("Test", images: [], options: ChatProviderOptions(), onStreamEvent: nil)
        let cliResult = try await cliProvider.sendMessage("Test", images: [], options: ChatProviderOptions(), onStreamEvent: nil)

        #expect(apiResult.content == "API response")
        #expect(apiResult.sessionId == nil)
        #expect(cliResult.content == "CLI response")
        #expect(cliResult.sessionId == "cli-session")
    }

    @Test func providerPropertiesAreDistinct() {
        let api = IntegrationMockProvider(name: "anthropic", displayName: "Claude API", supportsSessionHistory: false)
        let cli = IntegrationMockProvider(name: "claude-cli", displayName: "Claude Code", supportsSessionHistory: true)

        #expect(api.name == "anthropic")
        #expect(api.displayName == "Claude API")
        #expect(api.supportsSessionHistory == false)

        #expect(cli.name == "claude-cli")
        #expect(cli.displayName == "Claude Code")
        #expect(cli.supportsSessionHistory == true)
    }

    @Test func sessionHistoryOnlyAvailableForSupportingProviders() async {
        let noHistory = IntegrationMockProvider(supportsSessionHistory: false)
        let hasHistory = IntegrationMockProvider(supportsSessionHistory: true)
        let now = Date()
        await hasHistory.setSessions([
            ChatSession(id: "s1", lastModified: now, summary: "Session")
        ])

        #expect(noHistory.supportsSessionHistory == false)
        #expect(hasHistory.supportsSessionHistory == true)

        let sessions = await hasHistory.listSessions(workingDirectory: "/tmp")
        #expect(sessions.count == 1)
    }
}

// MARK: - ChatSettings Validation Tests

struct ChatSettingsValidationTests {

    @Test func defaultSettingsAreReasonable() {
        let settings = ChatSettings()
        #expect(settings.enableStreaming == true)
        #expect(settings.resumeLastSession == true)
        #expect(settings.verboseMode == false)
        #expect(settings.maxThinkingTokens >= 1024)
    }

    @Test func settingsCanBeModified() {
        let settings = ChatSettings()
        settings.enableStreaming = false
        settings.resumeLastSession = false
        settings.verboseMode = true
        settings.maxThinkingTokens = 4096

        #expect(settings.enableStreaming == false)
        #expect(settings.resumeLastSession == false)
        #expect(settings.verboseMode == true)
        #expect(settings.maxThinkingTokens == 4096)
    }
}

// MARK: - Adapter End-to-End Tests

struct AIClientChatAdapterEndToEndTests {

    @Test func fullConversationFlowWithSessionListable() async throws {
        let client = SessionAwareClient()
        let adapter = AIClientChatAdapter(client: client)

        #expect(adapter.supportsSessionHistory == true)
        #expect(adapter.displayName == "Test Provider")

        // Send first message
        let result1 = try await adapter.sendMessage(
            "Hello",
            images: [],
            options: ChatProviderOptions(workingDirectory: "/project"),
            onStreamEvent: nil
        )
        #expect(result1.sessionId == "test-session")
        #expect(result1.content == "Test response")

        // Resume with session ID
        let result2 = try await adapter.sendMessage(
            "Follow up",
            images: [],
            options: ChatProviderOptions(sessionId: result1.sessionId, workingDirectory: "/project"),
            onStreamEvent: nil
        )
        #expect(result2.sessionId == "test-session")
        #expect(client.lastSessionId == "test-session")

        // List sessions
        let sessions = await adapter.listSessions(workingDirectory: "/project")
        #expect(sessions.count == 1)

        // Load session messages
        let messages = await adapter.loadSessionMessages(sessionId: "test-session", workingDirectory: "/project")
        #expect(messages.count == 2)
    }

    @Test func fullConversationFlowWithPlainClient() async throws {
        let client = PlainClient()
        let adapter = AIClientChatAdapter(client: client)

        #expect(adapter.supportsSessionHistory == false)

        let result = try await adapter.sendMessage(
            "Hello",
            images: [],
            options: ChatProviderOptions(),
            onStreamEvent: nil
        )
        #expect(result.content == "Plain response")
        #expect(result.sessionId == nil)

        let sessions = await adapter.listSessions(workingDirectory: "/tmp")
        #expect(sessions.isEmpty)
    }

    @Test func streamingWithAccumulation() async throws {
        let client = StreamingClient()
        let adapter = AIClientChatAdapter(client: client)
        var textChunks: [String] = []
        var otherEvents: [AIStreamEvent] = []

        _ = try await adapter.sendMessage(
            "Explain something",
            images: [],
            options: ChatProviderOptions()
        ) { event in
            switch event {
            case .textDelta(let text): textChunks.append(text)
            default: otherEvents.append(event)
            }
        }

        #expect(textChunks == ["Hello", " ", "world", "!"])
        #expect(otherEvents.count == 2) // thinking + metrics
    }
}

// MARK: - Helper Types

private actor BasicMockProvider: ChatProvider {
    let displayName = "Basic"
    let name = "basic"

    func sendMessage(
        _ message: String,
        images: [ImageAttachment],
        options: ChatProviderOptions,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> ChatProviderResult {
        ChatProviderResult(content: "OK", sessionId: nil)
    }
}

private extension IntegrationMockProvider {
    func setStreamEvents(_ events: [AIStreamEvent]) {
        streamEventsToEmit = events
    }

    func setSessions(_ sessions: [ChatSession]) {
        stubbedSessions = sessions
    }

    func setSessionMessages(_ messages: [ChatSessionMessage]) {
        stubbedSessionMessages = messages
    }
}

private final class SessionAwareClient: AIClient, SessionListable, @unchecked Sendable {
    let displayName = "Test Provider"
    let name = "test"
    var lastSessionId: String?

    func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        lastSessionId = options.sessionId
        return AIClientResult(exitCode: 0, sessionId: "test-session", stderr: "", stdout: "Test response")
    }

    func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        fatalError("Not used")
    }

    func listSessions(workingDirectory: String) async -> [ChatSession] {
        [ChatSession(id: "test-session", lastModified: Date(), summary: "Test session")]
    }

    func loadSessionMessages(sessionId: String, workingDirectory: String) async -> [ChatSessionMessage] {
        [
            ChatSessionMessage(content: "Hello", role: .user),
            ChatSessionMessage(content: "Test response", role: .assistant),
        ]
    }

    func getSessionDetails(sessionId: String, summary: String, lastModified: Date, workingDirectory: String) -> SessionDetails? {
        nil
    }
}

private final class PlainClient: AIClient, @unchecked Sendable {
    let displayName = "Plain Provider"
    let name = "plain"

    func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        AIClientResult(exitCode: 0, sessionId: nil, stderr: "", stdout: "Plain response")
    }

    func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        fatalError("Not used")
    }
}

private final class StreamingClient: AIClient, @unchecked Sendable {
    let displayName = "Streaming"
    let name = "streaming"

    func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        onStreamEvent?(.thinking("Let me think..."))
        onStreamEvent?(.textDelta("Hello"))
        onStreamEvent?(.textDelta(" "))
        onStreamEvent?(.textDelta("world"))
        onStreamEvent?(.textDelta("!"))
        onStreamEvent?(.metrics(duration: 2.0, cost: 0.01, turns: 1))
        return AIClientResult(exitCode: 0, sessionId: "s1", stderr: "", stdout: "Hello world!")
    }

    func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        fatalError("Not used")
    }
}
