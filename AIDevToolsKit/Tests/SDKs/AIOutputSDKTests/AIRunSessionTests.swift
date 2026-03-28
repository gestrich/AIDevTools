import Foundation
import Testing
@testable import AIOutputSDK

@Suite struct AIRunSessionTests {

    // MARK: - Helpers

    private func makeSession(
        key: String = "test-key",
        client: (any AIClient)? = nil
    ) -> (AIRunSession, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIRunSessionTests-\(UUID().uuidString)")
        let store = AIOutputStore(baseDirectory: dir)
        if let client {
            return (AIRunSession(key: key, store: store, client: client), dir)
        }
        return (AIRunSession(key: key, store: store), dir)
    }

    // MARK: - run(prompt:) tests

    @Test func runCallsClientAndPersistsStdout() async throws {
        let client = MockAIClient(
            runResult: AIClientResult(exitCode: 0, stderr: "", stdout: "raw output")
        )
        let (session, dir) = makeSession(client: client)
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = try await session.run(prompt: "test prompt")

        #expect(result.stdout == "raw output")
        #expect(session.loadOutput() == "raw output")
    }

    @Test func runForwardsFormattedOutputToCallback() async throws {
        let client = MockAIClient(
            runResult: AIClientResult(exitCode: 0, stderr: "", stdout: "raw"),
            onRunOutput: ["chunk1", "chunk2"]
        )
        let (session, dir) = makeSession(client: client)
        defer { try? FileManager.default.removeItem(at: dir) }

        let received = ChunkCollector()
        _ = try await session.run(prompt: "test", onOutput: { chunk in
            received.append(chunk)
        })

        #expect(received.chunks == ["chunk1", "chunk2"])
    }

    @Test func runPassesOptionsToClient() async throws {
        let client = MockAIClient(
            runResult: AIClientResult(exitCode: 0, stderr: "", stdout: "")
        )
        let (session, dir) = makeSession(client: client)
        defer { try? FileManager.default.removeItem(at: dir) }

        let options = AIClientOptions(model: "opus", workingDirectory: "/tmp")
        _ = try await session.run(prompt: "test", options: options)

        #expect(client.lastRunOptions?.model == "opus")
        #expect(client.lastRunOptions?.workingDirectory == "/tmp")
    }

    @Test func runThrowsNoClientError() async {
        let (session, dir) = makeSession()
        defer { try? FileManager.default.removeItem(at: dir) }

        await #expect(throws: AIRunSessionError.self) {
            try await session.run(prompt: "test")
        }
    }

    // MARK: - runStructured() tests

    @Test func runStructuredPersistsRawOutput() async throws {
        let client = MockAIClient(
            structuredRawOutput: "{\"name\":\"test\"}",
            structuredValue: SimpleValue(name: "test")
        )
        let (session, dir) = makeSession(client: client)
        defer { try? FileManager.default.removeItem(at: dir) }

        let result: AIStructuredResult<SimpleValue> = try await session.runStructured(
            SimpleValue.self,
            prompt: "test",
            jsonSchema: "{}"
        )

        #expect(result.value.name == "test")
        #expect(session.loadOutput() == "{\"name\":\"test\"}")
    }

    @Test func runStructuredThrowsNoClientError() async {
        let (session, dir) = makeSession()
        defer { try? FileManager.default.removeItem(at: dir) }

        await #expect(throws: AIRunSessionError.self) {
            let _: AIStructuredResult<SimpleValue> = try await session.runStructured(
                SimpleValue.self,
                prompt: "test",
                jsonSchema: "{}"
            )
        }
    }

    // MARK: - Output access

    @Test func loadOutputReturnsPersistedOutput() async throws {
        let client = MockAIClient(
            runResult: AIClientResult(exitCode: 0, stderr: "", stdout: "persisted")
        )
        let (session, dir) = makeSession(client: client)
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try await session.run(prompt: "test")
        #expect(session.loadOutput() == "persisted")
    }

    @Test func loadOutputReturnsNilForUnknownKey() {
        let (session, dir) = makeSession(key: "never-written")
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(session.loadOutput() == nil)
    }

    @Test func deleteOutputRemovesStoredOutput() async throws {
        let client = MockAIClient(
            runResult: AIClientResult(exitCode: 0, stderr: "", stdout: "content")
        )
        let (session, dir) = makeSession(client: client)
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try await session.run(prompt: "test")
        #expect(session.loadOutput() == "content")

        try session.deleteOutput()
        #expect(session.loadOutput() == nil)
    }

    @Test func readOnlySessionCanLoadAndDelete() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIRunSessionTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AIOutputStore(baseDirectory: dir)
        try store.write(output: "existing data", key: "readonly-key")

        let session = AIRunSession(key: "readonly-key", store: store)
        #expect(session.loadOutput() == "existing data")

        try session.deleteOutput()
        #expect(session.loadOutput() == nil)
    }

    // MARK: - Legacy closure-based API

    @Test func legacyRunAccumulatesAndPersists() async throws {
        let (session, dir) = makeSession()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = try await session.run { handler in
            handler("hello ")
            handler("world")
        }

        #expect(result == "hello world")
        #expect(session.loadOutput() == "hello world")
    }
}

// MARK: - Test doubles

private struct SimpleValue: Codable, Sendable {
    let name: String
}

private final class MockAIClient: AIClient, @unchecked Sendable {
    let name = "mock"
    let displayName = "Mock"

    let runResult: AIClientResult?
    let onRunOutput: [String]
    let structuredRawOutput: String
    let structuredValue: (any Sendable)?
    var lastRunOptions: AIClientOptions?

    init(
        runResult: AIClientResult? = nil,
        onRunOutput: [String] = [],
        structuredRawOutput: String = "",
        structuredValue: (any Sendable)? = nil
    ) {
        self.onRunOutput = onRunOutput
        self.runResult = runResult
        self.structuredRawOutput = structuredRawOutput
        self.structuredValue = structuredValue
    }

    func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        lastRunOptions = options
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
        lastRunOptions = options
        let value = structuredValue as! T
        return AIStructuredResult(rawOutput: structuredRawOutput, stderr: "", value: value)
    }
}

private final class ChunkCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _chunks: [String] = []

    func append(_ chunk: String) {
        lock.lock()
        defer { lock.unlock() }
        _chunks.append(chunk)
    }

    var chunks: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _chunks
    }
}
