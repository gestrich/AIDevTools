import Testing
import Foundation
import EvalService
import EvalFeature
import EvalSDK

enum IntegrationTest {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["ENABLE_INTEGRATION_TESTS"] != nil
    }
}

extension EvalCase: CustomTestStringConvertible {
    public var testDescription: String {
        if let suite {
            return "\(suite).\(id)"
        }
        return id
    }
}

private func createEvalTempDirectory() throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("eval-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let emptySchema = "{}"
    try emptySchema.write(to: tempDir.appendingPathComponent("result_schema.json"), atomically: true, encoding: .utf8)
    try emptySchema.write(to: tempDir.appendingPathComponent("rubric_schema.json"), atomically: true, encoding: .utf8)

    return tempDir
}

func runEval(_ eval: EvalCase, provider: Provider = .claude) async throws {
    let adapter: any ProviderAdapterProtocol = switch provider {
    case .claude: ClaudeAdapter()
    case .codex: CodexAdapter()
    }

    let tempDir = try createEvalTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let useCase = RunCaseUseCase(adapter: adapter)
    let result = try await useCase.run(
        RunCaseUseCase.Options(
            evalCase: eval,
            resultSchemaPath: tempDir.appendingPathComponent("result_schema.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rubric_schema.json"),
            artifactsDirectory: tempDir.appendingPathComponent("artifacts"),
            provider: provider,
            repoRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        )
    )

    #expect(result.passed, "Case \(eval.id) failed: \(result.errors.joined(separator: ", "))")
}

func runEvalExpectingFailure(_ eval: EvalCase, provider: Provider = .claude) async throws {
    let adapter: any ProviderAdapterProtocol = switch provider {
    case .claude: ClaudeAdapter()
    case .codex: CodexAdapter()
    }

    let tempDir = try createEvalTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let useCase = RunCaseUseCase(adapter: adapter)
    let result = try await useCase.run(
        RunCaseUseCase.Options(
            evalCase: eval,
            resultSchemaPath: tempDir.appendingPathComponent("result_schema.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rubric_schema.json"),
            artifactsDirectory: tempDir.appendingPathComponent("artifacts"),
            provider: provider,
            repoRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        )
    )

    #expect(!result.passed, "Case \(eval.id) should have failed but passed — negative test not caught")
    #expect(!result.errors.isEmpty, "Case \(eval.id) should have produced errors")
}

extension Tag {
    @Tag static var integration: Self
}
