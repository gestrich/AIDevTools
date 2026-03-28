import AIOutputSDK
import Foundation

struct MockAIClient: AIClient, Sendable {
    let name: String
    let displayName: String

    init(name: String, displayName: String? = nil) {
        self.name = name
        self.displayName = displayName ?? name.capitalized
    }

    func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        AIClientResult(exitCode: 0, stderr: "", stdout: "")
    }

    func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        throw NSError(domain: "MockAIClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
}
