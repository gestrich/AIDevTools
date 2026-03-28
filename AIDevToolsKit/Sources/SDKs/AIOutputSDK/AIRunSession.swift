import Foundation

public struct AIRunSession: Sendable {

    public let client: (any AIClient)?
    public let key: String
    public let store: AIOutputStore

    public init(key: String, store: AIOutputStore, client: any AIClient) {
        self.client = client
        self.key = key
        self.store = store
    }

    public init(key: String, store: AIOutputStore) {
        self.client = nil
        self.key = key
        self.store = store
    }

    // MARK: - Active execution (requires client)

    @discardableResult
    public func run(
        prompt: String,
        options: AIClientOptions = AIClientOptions(),
        onOutput: (@Sendable (String) -> Void)? = nil,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)? = nil
    ) async throws -> AIClientResult {
        guard let client else {
            throw AIRunSessionError.noClient
        }
        do {
            let result = try await client.run(prompt: prompt, options: options, onOutput: onOutput, onStreamEvent: onStreamEvent)
            try? store.write(output: result.stdout, key: key)
            return result
        } catch {
            throw error
        }
    }

    public func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions = AIClientOptions(),
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> AIStructuredResult<T> {
        guard let client else {
            throw AIRunSessionError.noClient
        }
        let result = try await client.runStructured(
            type,
            prompt: prompt,
            jsonSchema: jsonSchema,
            options: options,
            onOutput: onOutput
        )
        try? store.write(output: result.rawOutput, key: key)
        return result
    }

    // MARK: - Legacy closure-based execution

    @available(*, deprecated, message: "Use run(prompt:options:onOutput:) instead")
    @discardableResult
    public func run(
        onOutput: (@Sendable (String) -> Void)? = nil,
        work: @Sendable (_ outputHandler: @escaping @Sendable (String) -> Void) async throws -> Void
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

    // MARK: - Output access

    public func loadOutput() -> String? {
        store.read(key: key)
    }

    public func deleteOutput() throws {
        try store.delete(key: key)
    }
}

public enum AIRunSessionError: Error, LocalizedError {
    case noClient

    public var errorDescription: String? {
        switch self {
        case .noClient:
            return "AIRunSession has no client configured — use init(key:store:client:) to enable execution"
        }
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
