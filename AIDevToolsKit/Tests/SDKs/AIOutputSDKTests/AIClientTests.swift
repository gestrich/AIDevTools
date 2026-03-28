import Foundation
import Testing
@testable import AIOutputSDK

@Suite struct AIClientTests {

    // MARK: - AIClientOptions

    @Test func optionsDefaultValues() {
        let options = AIClientOptions()
        #expect(options.dangerouslySkipPermissions == false)
        #expect(options.environment == nil)
        #expect(options.jsonSchema == nil)
        #expect(options.model == nil)
        #expect(options.workingDirectory == nil)
    }

    @Test func optionsCustomValues() {
        let options = AIClientOptions(
            dangerouslySkipPermissions: true,
            environment: ["KEY": "VALUE"],
            jsonSchema: "{\"type\":\"object\"}",
            model: "opus",
            workingDirectory: "/tmp"
        )
        #expect(options.dangerouslySkipPermissions == true)
        #expect(options.environment == ["KEY": "VALUE"])
        #expect(options.jsonSchema == "{\"type\":\"object\"}")
        #expect(options.model == "opus")
        #expect(options.workingDirectory == "/tmp")
    }

    // MARK: - AIClientResult

    @Test func resultStoresValues() {
        let result = AIClientResult(exitCode: 0, stderr: "warn", stdout: "output")
        #expect(result.exitCode == 0)
        #expect(result.stderr == "warn")
        #expect(result.stdout == "output")
    }

    // MARK: - AIStructuredResult

    @Test func structuredResultStoresValues() {
        let result = AIStructuredResult(rawOutput: "{}", stderr: "", value: "decoded")
        #expect(result.rawOutput == "{}")
        #expect(result.stderr == "")
        #expect(result.value == "decoded")
    }

    // MARK: - Sendable conformance (compile-time checks)

    @Test func typesSendable() {
        func assertSendable<T: Sendable>(_: T.Type) {}
        assertSendable(AIClientOptions.self)
        assertSendable(AIClientResult.self)
        assertSendable(AIStructuredResult<String>.self)
    }

    // MARK: - AIClient protocol conformance (compile-time check)

    @Test func mockClientConformsToProtocol() async throws {
        let client: any AIClient = MockAIClient()
        let result = try await client.run(
            prompt: "test",
            options: AIClientOptions(),
            onOutput: nil
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout == "mock output")

        let structured: AIStructuredResult<String> = try await client.runStructured(
            String.self,
            prompt: "test",
            jsonSchema: "{}",
            options: AIClientOptions(),
            onOutput: nil
        )
        #expect(structured.value == "mock value")
        #expect(structured.rawOutput == "raw")
    }
}

private struct MockAIClient: AIClient {
    let name = "mock"
    let displayName = "Mock"

    func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        onOutput?("mock output")
        return AIClientResult(exitCode: 0, stderr: "", stdout: "mock output")
    }

    func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        let value = "mock value" as! T
        return AIStructuredResult(rawOutput: "raw", stderr: "", value: value)
    }
}
