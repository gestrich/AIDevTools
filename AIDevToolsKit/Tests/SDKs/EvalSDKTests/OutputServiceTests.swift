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

    @Test func writeAndReadRoundTrip() throws {
        // Arrange
        let outputDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let config = makeConfiguration(outputDir: outputDir)
        let result = ProviderResult(provider: .claude)

        // Act
        let updated = try service.write(result: result, stdout: "hello stdout", stderr: "hello stderr", configuration: config)
        let rawContents = try String(contentsOf: updated.rawStdoutPath!, encoding: .utf8)

        // Assert
        #expect(rawContents == "hello stdout")
    }

    @Test func writeCreatesStdoutAndStderrFiles() throws {
        // Arrange
        let outputDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let config = makeConfiguration(outputDir: outputDir)
        let result = ProviderResult(provider: .claude)

        // Act
        let updated = try service.write(result: result, stdout: "out", stderr: "err", configuration: config)

        // Assert
        #expect(updated.rawStdoutPath != nil)
        #expect(updated.rawStderrPath != nil)
        #expect(FileManager.default.fileExists(atPath: updated.rawStdoutPath!.path))
        #expect(FileManager.default.fileExists(atPath: updated.rawStderrPath!.path))
    }

    @Test func stdoutPathUsesExpectedLayout() throws {
        // Arrange
        let outputDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let config = makeConfiguration(outputDir: outputDir, provider: .claude, caseId: "my-suite.my-case")
        let result = ProviderResult(provider: .claude)

        // Act
        let updated = try service.write(result: result, stdout: "content", stderr: "", configuration: config)

        // Assert
        let expected = outputDir
            .appendingPathComponent("artifacts/raw/claude/my-suite.my-case.stdout")
        #expect(updated.rawStdoutPath == expected)
    }

    @Test func readMissingOutputThrows() {
        // Arrange
        let outputDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }

        // Act & Assert
        #expect(throws: OutputServiceError.self) {
            try service.readFormattedOutput(caseId: "missing", provider: .claude, outputDirectory: outputDir)
        }
    }

    @Test func writeOverwritesPreviousOutput() throws {
        // Arrange
        let outputDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let config = makeConfiguration(outputDir: outputDir)
        let result = ProviderResult(provider: .claude)

        // Act
        _ = try service.write(result: result, stdout: "first", stderr: "", configuration: config)
        let updated = try service.write(result: result, stdout: "second", stderr: "", configuration: config)
        let rawContents = try String(contentsOf: updated.rawStdoutPath!, encoding: .utf8)

        // Assert
        #expect(rawContents == "second")
    }
}
