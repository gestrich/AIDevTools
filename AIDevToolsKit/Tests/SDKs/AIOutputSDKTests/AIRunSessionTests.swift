import Foundation
import Testing
@testable import AIOutputSDK

@Suite struct AIRunSessionTests {

    private func makeSession(key: String = "test-key") -> (AIRunSession, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIRunSessionTests-\(UUID().uuidString)")
        let store = AIOutputStore(baseDirectory: dir)
        return (AIRunSession(key: key, store: store), dir)
    }

    @Test func runAccumulatesAndPersists() async throws {
        let (session, dir) = makeSession()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = try await session.run { handler in
            handler("hello ")
            handler("world")
        }

        #expect(result == "hello world")
        #expect(session.loadOutput() == "hello world")
    }

    @Test func runForwardsChunksToOnOutput() async throws {
        let (session, dir) = makeSession()
        defer { try? FileManager.default.removeItem(at: dir) }

        let received = ChunkCollector()
        try await session.run(onOutput: { chunk in
            received.append(chunk)
        }) { handler in
            handler("a")
            handler("b")
            handler("c")
        }

        let chunks = received.chunks
        #expect(chunks == ["a", "b", "c"])
    }

    @Test func runPersistsPartialOutputOnFailure() async throws {
        let (session, dir) = makeSession()
        defer { try? FileManager.default.removeItem(at: dir) }

        struct TestError: Error {}

        do {
            try await session.run { handler in
                handler("partial ")
                handler("output")
                throw TestError()
            }
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is TestError)
        }

        #expect(session.loadOutput() == "partial output")
    }

    @Test func loadOutputReturnsNilForUnknownKey() {
        let (session, dir) = makeSession(key: "never-written")
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(session.loadOutput() == nil)
    }

    @Test func deleteOutputRemovesStoredOutput() async throws {
        let (session, dir) = makeSession()
        defer { try? FileManager.default.removeItem(at: dir) }

        try await session.run { handler in
            handler("content")
        }
        #expect(session.loadOutput() == "content")

        try session.deleteOutput()
        #expect(session.loadOutput() == nil)
    }

    @Test func returnValueMatchesAccumulatedOutput() async throws {
        let (session, dir) = makeSession()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = try await session.run { handler in
            handler("chunk1")
            handler("chunk2")
            handler("chunk3")
        }

        #expect(result == "chunk1chunk2chunk3")
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
