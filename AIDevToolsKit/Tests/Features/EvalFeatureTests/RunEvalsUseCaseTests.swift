import Testing
import Foundation
@testable import EvalFeature
@testable import EvalService
@testable import EvalSDK

@Suite("RunEvalsUseCase")
struct RunEvalsUseCaseTests {

    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("RunEvalsUseCaseTests-\(UUID().uuidString)")

    private func createTestDirectories(cases: [String]) throws -> (casesDir: URL, outputDir: URL) {
        let id = UUID().uuidString
        let casesRoot = tempDir.appendingPathComponent("cases-\(id)")
        let casesDir = casesRoot.appendingPathComponent("cases")
        try FileManager.default.createDirectory(at: casesDir, withIntermediateDirectories: true)

        let jsonl = cases.joined(separator: "\n")
        try jsonl.write(to: casesDir.appendingPathComponent("test-suite.jsonl"), atomically: true, encoding: .utf8)

        let outputDir = tempDir.appendingPathComponent("output-\(id)")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let resultSchema = "{}"
        try resultSchema.write(to: outputDir.appendingPathComponent("result_output_schema.json"), atomically: true, encoding: .utf8)
        try resultSchema.write(to: outputDir.appendingPathComponent("rubric_output_schema.json"), atomically: true, encoding: .utf8)

        return (casesRoot, outputDir)
    }

    @Test func progressCallbackReceivesUpdates() async throws {
        let (casesDir, outputDir) = try createTestDirectories(cases: [
            #"{"id": "case-1", "task": "Do A", "input": "input-a", "expected": "hello"}"#,
            #"{"id": "case-2", "task": "Do B", "input": "input-b", "expected": "world"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let adapter = MockProviderAdapter(result: ProviderResult(
            provider: .claude,
            resultText: "hello"
        ))
        let useCase = RunEvalsUseCase(providers: [
            .init(provider: .claude, adapter: adapter)
        ])

        var progressUpdates: [RunEvalsUseCase.Progress] = []
        let options = RunEvalsUseCase.Options(
            casesDirectory: casesDir,
            outputDirectory: outputDir,
            providers: [.claude],
            repoRoot: tempDir
        )

        _ = try await useCase.run(options) { progress in
            progressUpdates.append(progress)
        }

        // startingProvider + (startingCase + completedCase) * 2 + completedProvider = 6
        #expect(progressUpdates.count == 6)

        guard case .startingProvider(let provider, let caseCount) = progressUpdates[0] else {
            Issue.record("Expected startingProvider"); return
        }
        #expect(provider == "claude")
        #expect(caseCount == 2)

        guard case .startingCase(_, let index, let total, _, _) = progressUpdates[1] else {
            Issue.record("Expected startingCase"); return
        }
        #expect(index == 0)
        #expect(total == 2)

        guard case .completedCase(let result, _, _, _) = progressUpdates[2] else {
            Issue.record("Expected completedCase"); return
        }
        #expect(result.caseId == "test-suite.case-1")

        guard case .completedProvider(let summary) = progressUpdates[5] else {
            Issue.record("Expected completedProvider"); return
        }
        #expect(summary.provider == "claude")
        #expect(summary.total == 2)
    }

    @Test func returnsSummaryWithCorrectCounts() async throws {
        let (casesDir, outputDir) = try createTestDirectories(cases: [
            #"{"id": "pass-1", "task": "T", "input": "I", "expected": "match"}"#,
            #"{"id": "fail-1", "task": "T", "input": "I", "expected": "no-match"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let adapter = MockProviderAdapter(result: ProviderResult(
            provider: .claude,
            resultText: "match"
        ))
        let useCase = RunEvalsUseCase(providers: [
            .init(provider: .claude, adapter: adapter)
        ])

        let options = RunEvalsUseCase.Options(
            casesDirectory: casesDir,
            outputDirectory: outputDir,
            providers: [.claude],
            repoRoot: tempDir
        )

        let summaries = try await useCase.run(options)

        #expect(summaries.count == 1)
        #expect(summaries[0].total == 2)
        #expect(summaries[0].passed == 1)
        #expect(summaries[0].failed == 1)
        #expect(summaries[0].provider == "claude")
    }

    @Test func suiteFilterRestrictsCase() async throws {
        let (casesDir, outputDir) = try createTestDirectories(cases: [
            #"{"id": "case-1", "task": "T", "input": "I", "expected": "ok"}"#,
        ])
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let adapter = MockProviderAdapter(result: ProviderResult(
            provider: .claude,
            resultText: "ok"
        ))
        let useCase = RunEvalsUseCase(providers: [
            .init(provider: .claude, adapter: adapter)
        ])

        let options = RunEvalsUseCase.Options(
            casesDirectory: casesDir,
            outputDirectory: outputDir,
            suite: "nonexistent-suite",
            providers: [.claude],
            repoRoot: tempDir
        )

        let summaries = try await useCase.run(options)

        #expect(summaries.isEmpty)
    }
}
