import Foundation

public struct AIRunSession: Sendable {

    public let key: String
    public let store: AIOutputStore

    public init(key: String, store: AIOutputStore) {
        self.key = key
        self.store = store
    }

    @discardableResult
    public func run(
        onOutput: (@Sendable (String) -> Void)? = nil,
        work: @Sendable (_ outputHandler: @Sendable (String) -> Void) async throws -> Void
    ) async throws -> String {
        let accumulator = Accumulator()

        let handler: @Sendable (String) -> Void = { chunk in
            accumulator.append(chunk)
            onOutput?(chunk)
        }

        do {
            try await work(handler)
            let output = accumulator.value
            try? store.write(output: output, key: key)
            return output
        } catch {
            let output = accumulator.value
            try? store.write(output: output, key: key)
            throw error
        }
    }

    public func loadOutput() -> String? {
        store.read(key: key)
    }

    public func deleteOutput() throws {
        try store.delete(key: key)
    }
}

private final class Accumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    func append(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        buffer += text
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}
