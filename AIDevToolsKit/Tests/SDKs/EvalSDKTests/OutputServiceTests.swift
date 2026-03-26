import AIOutputSDK
import Foundation
import Testing
@testable import EvalSDK
@testable import EvalService

@Suite struct OutputServiceTests {

    private let service = OutputService()

    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("OutputServiceTests-\(UUID().uuidString)")
    }

    private func makeConfiguration(outputDir: URL, provider: Provider = .claude, caseId: String = "test-case") -> RunConfiguration {
        RunConfiguration(
            prompt: "test prompt",
            outputSchemaPath: outputDir.appendingPathComponent("schema.json"),
            artifactsDirectory: OutputService.artifactsDirectory(outputDirectory: outputDir),
            provider: provider,
            caseId: caseId
        )
    }

    private func writeWithSession(
        result: ProviderResult,
        stdout: String,
        stderr: String,
        configuration: RunConfiguration
    ) throws -> ProviderResult {
        let session = OutputService.makeSession(
            artifactsDirectory: configuration.artifactsDirectory,
            provider: configuration.provider.rawValue,
            caseId: configuration.caseId
        )
        try session.store.write(output: stdout, key: session.key)
        return try service.writeArtifacts(
            result: result,
            stderr: stderr,
            session: session,
            configuration: configuration
        )
    }

    @Test func writeAndReadRoundTrip() throws {
        let outputDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let config = makeConfiguration(outputDir: outputDir)
        let result = ProviderResult(provider: .claude)

        let updated = try writeWithSession(result: result, stdout: "hello stdout", stderr: "hello stderr", configuration: config)
        let rawContents = try String(contentsOf: updated.rawStdoutPath!, encoding: .utf8)

        #expect(rawContents == "hello stdout")
    }

    @Test func writeCreatesStdoutAndStderrFiles() throws {
        let outputDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let config = makeConfiguration(outputDir: outputDir)
        let result = ProviderResult(provider: .claude)

        let updated = try writeWithSession(result: result, stdout: "out", stderr: "err", configuration: config)

        #expect(updated.rawStdoutPath != nil)
        #expect(updated.rawStderrPath != nil)
        #expect(FileManager.default.fileExists(atPath: updated.rawStdoutPath!.path))
        #expect(FileManager.default.fileExists(atPath: updated.rawStderrPath!.path))
    }

    @Test func stdoutPathUsesExpectedLayout() throws {
        let outputDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let config = makeConfiguration(outputDir: outputDir, provider: .claude, caseId: "my-suite.my-case")
        let result = ProviderResult(provider: .claude)

        let updated = try writeWithSession(result: result, stdout: "content", stderr: "", configuration: config)

        let expected = outputDir
            .appendingPathComponent("artifacts/raw/claude/my-suite.my-case.stdout")
        #expect(updated.rawStdoutPath == expected)
    }

    @Test func readMissingOutputThrows() {
        let outputDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }

        #expect(throws: OutputServiceError.self) {
            try service.readFormattedOutput(caseId: "missing", provider: .claude, outputDirectory: outputDir)
        }
    }

    @Test func writeOverwritesPreviousOutput() throws {
        let outputDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let config = makeConfiguration(outputDir: outputDir)
        let result = ProviderResult(provider: .claude)

        _ = try writeWithSession(result: result, stdout: "first", stderr: "", configuration: config)
        let updated = try writeWithSession(result: result, stdout: "second", stderr: "", configuration: config)
        let rawContents = try String(contentsOf: updated.rawStdoutPath!, encoding: .utf8)

        #expect(rawContents == "second")
    }
}
