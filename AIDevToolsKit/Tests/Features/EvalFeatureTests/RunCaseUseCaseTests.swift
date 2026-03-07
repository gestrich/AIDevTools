import Testing
import Foundation
@testable import EvalFeature
@testable import EvalService
@testable import EvalSDK

@Suite("RunCaseUseCase")
struct RunCaseUseCaseTests {

    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("RunCaseUseCaseTests-\(UUID().uuidString)")

    var defaultOptions: RunCaseUseCase.Options {
        RunCaseUseCase.Options(
            evalCase: EvalCase(id: "test-1", suite: "suite-a", task: "Do something", input: "some input"),
            resultSchemaPath: tempDir.appendingPathComponent("result.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rubric.json"),
            artifactsDirectory: tempDir.appendingPathComponent("artifacts"),
            provider: .claude,
            repoRoot: tempDir
        )
    }

    // MARK: - Passing Cases

    @Test func passingCaseWithExactMatch() async throws {
        let evalCase = EvalCase(id: "exact-1", suite: "suite", task: "task", input: "input", expected: "hello world")
        let adapter = MockProviderAdapter(result: ProviderResult(
            provider: .claude,
            resultText: "hello world"
        ))
        let useCase = RunCaseUseCase(adapter: adapter)
        let options = RunCaseUseCase.Options(
            evalCase: evalCase,
            resultSchemaPath: tempDir.appendingPathComponent("r.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rub.json"),
            artifactsDirectory: tempDir.appendingPathComponent("art"),
            provider: .claude,
            repoRoot: tempDir
        )

        let result = try await useCase.run(options)

        #expect(result.passed)
        #expect(result.errors.isEmpty)
        #expect(result.caseId == "suite.exact-1")
    }

    @Test func passingCaseWithMustInclude() async throws {
        let evalCase = EvalCase(id: "mi-1", suite: "s", task: "task", input: "input", mustInclude: ["Button", "action"])
        let adapter = MockProviderAdapter(result: ProviderResult(
            provider: .claude,
            resultText: "Button(action: { })"
        ))
        let useCase = RunCaseUseCase(adapter: adapter)
        let options = RunCaseUseCase.Options(
            evalCase: evalCase,
            resultSchemaPath: tempDir.appendingPathComponent("r.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rub.json"),
            artifactsDirectory: tempDir.appendingPathComponent("art"),
            provider: .claude,
            repoRoot: tempDir
        )

        let result = try await useCase.run(options)

        #expect(result.passed)
        #expect(result.errors.isEmpty)
    }

    // MARK: - Failing Cases

    @Test func failingExactMatch() async throws {
        let evalCase = EvalCase(id: "fail-1", suite: "s", task: "task", input: "input", expected: "Color.gray1")
        let adapter = MockProviderAdapter(result: ProviderResult(
            provider: .claude,
            resultText: "Color.blue5"
        ))
        let useCase = RunCaseUseCase(adapter: adapter)
        let options = RunCaseUseCase.Options(
            evalCase: evalCase,
            resultSchemaPath: tempDir.appendingPathComponent("r.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rub.json"),
            artifactsDirectory: tempDir.appendingPathComponent("art"),
            provider: .claude,
            repoRoot: tempDir
        )

        let result = try await useCase.run(options)

        #expect(!result.passed)
        #expect(result.errors.contains(where: { $0.contains("exact output mismatch") }))
    }

    @Test func failingMustNotInclude() async throws {
        let evalCase = EvalCase(id: "fail-2", suite: "s", task: "task", input: "input", mustNotInclude: ["dkColor"])
        let adapter = MockProviderAdapter(result: ProviderResult(
            provider: .claude,
            resultText: "let c = dkColor(.gray)"
        ))
        let useCase = RunCaseUseCase(adapter: adapter)
        let options = RunCaseUseCase.Options(
            evalCase: evalCase,
            resultSchemaPath: tempDir.appendingPathComponent("r.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rub.json"),
            artifactsDirectory: tempDir.appendingPathComponent("art"),
            provider: .claude,
            repoRoot: tempDir
        )

        let result = try await useCase.run(options)

        #expect(!result.passed)
        #expect(result.errors.contains(where: { $0.contains("found forbidden substring") }))
    }

    // MARK: - Provider Error

    @Test func providerErrorReturnsFailure() async throws {
        let adapter = MockProviderAdapter(result: ProviderResult(
            provider: .claude,
            error: ProviderError(message: "CLI process exited with code 1")
        ))
        let useCase = RunCaseUseCase(adapter: adapter)

        let result = try await useCase.run(defaultOptions)

        #expect(!result.passed)
        #expect(result.errors.contains(where: { $0.contains("provider error") }))
        #expect(result.errors.contains(where: { $0.contains("CLI process exited with code 1") }))
    }

    // MARK: - Trace Writing

    @Test func tracesWrittenWhenKeepTracesEnabled() async throws {
        let artifactsDir = tempDir.appendingPathComponent("trace-test")
        let adapter = MockProviderAdapter(result: ProviderResult(
            provider: .claude,
            resultText: "ok",
            events: [["type": .string("assistant")]]
        ))
        let useCase = RunCaseUseCase(adapter: adapter)
        let options = RunCaseUseCase.Options(
            evalCase: EvalCase(id: "trace-1", suite: "s", task: "task", input: "input"),
            resultSchemaPath: tempDir.appendingPathComponent("r.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rub.json"),
            artifactsDirectory: artifactsDir,
            provider: .claude,
            keepTraces: true,
            repoRoot: tempDir
        )

        _ = try await useCase.run(options)

        let traceFile = artifactsDir.appendingPathComponent("traces/s.trace-1.jsonl")
        #expect(FileManager.default.fileExists(atPath: traceFile.path))
    }

    @Test func tracesNotWrittenWhenKeepTracesDisabled() async throws {
        let artifactsDir = tempDir.appendingPathComponent("no-trace-test")
        let adapter = MockProviderAdapter(result: ProviderResult(
            provider: .claude,
            resultText: "ok",
            events: [["type": .string("assistant")]]
        ))
        let useCase = RunCaseUseCase(adapter: adapter)
        let options = RunCaseUseCase.Options(
            evalCase: EvalCase(id: "trace-2", suite: "s", task: "task", input: "input"),
            resultSchemaPath: tempDir.appendingPathComponent("r.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rub.json"),
            artifactsDirectory: artifactsDir,
            provider: .claude,
            keepTraces: false,
            repoRoot: tempDir
        )

        _ = try await useCase.run(options)

        let tracesDir = artifactsDir.appendingPathComponent("traces")
        #expect(!FileManager.default.fileExists(atPath: tracesDir.path))
    }

    // MARK: - Rubric Grading

    @Test func rubricPassingCase() async throws {
        var callCount = 0
        var adapter = MockProviderAdapter()
        adapter.runHandler = { config in
            callCount += 1
            if callCount == 1 {
                return ProviderResult(provider: .claude, resultText: "migrated code")
            } else {
                return ProviderResult(
                    provider: .claude,
                    structuredOutput: [
                        "overall_pass": .bool(true),
                        "score": .int(9),
                        "checks": .array([
                            .object([
                                "id": .string("check1"),
                                "pass": .bool(true),
                                "notes": .string("good")
                            ])
                        ])
                    ]
                )
            }
        }

        let evalCase = EvalCase(
            id: "rubric-1",
            suite: "s",
            task: "task",
            input: "input",
            rubric: RubricConfig(prompt: "Grade this: {{result}}", requireOverallPass: true)
        )
        let useCase = RunCaseUseCase(adapter: adapter)
        let options = RunCaseUseCase.Options(
            evalCase: evalCase,
            resultSchemaPath: tempDir.appendingPathComponent("r.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rub.json"),
            artifactsDirectory: tempDir.appendingPathComponent("art"),
            provider: .claude,
            repoRoot: tempDir
        )

        let result = try await useCase.run(options)

        #expect(result.passed)
        #expect(callCount == 2)
    }

    @Test func rubricFailingCase() async throws {
        var callCount = 0
        var adapter = MockProviderAdapter()
        adapter.runHandler = { config in
            callCount += 1
            if callCount == 1 {
                return ProviderResult(provider: .claude, resultText: "bad code")
            } else {
                return ProviderResult(
                    provider: .claude,
                    structuredOutput: [
                        "overall_pass": .bool(false),
                        "score": .int(2),
                        "checks": .array([])
                    ]
                )
            }
        }

        let evalCase = EvalCase(
            id: "rubric-2",
            suite: "s",
            task: "task",
            input: "input",
            rubric: RubricConfig(prompt: "Grade: {{result}}", requireOverallPass: true)
        )
        let useCase = RunCaseUseCase(adapter: adapter)
        let options = RunCaseUseCase.Options(
            evalCase: evalCase,
            resultSchemaPath: tempDir.appendingPathComponent("r.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rub.json"),
            artifactsDirectory: tempDir.appendingPathComponent("art"),
            provider: .claude,
            repoRoot: tempDir
        )

        let result = try await useCase.run(options)

        #expect(!result.passed)
        #expect(result.errors.contains(where: { $0.contains("overall_pass") }))
    }

    @Test func rubricProviderErrorReturnsRubricError() async throws {
        var callCount = 0
        var adapter = MockProviderAdapter()
        adapter.runHandler = { config in
            callCount += 1
            if callCount == 1 {
                return ProviderResult(provider: .claude, resultText: "some result")
            } else {
                return ProviderResult(
                    provider: .claude,
                    error: ProviderError(message: "rubric CLI failed")
                )
            }
        }

        let evalCase = EvalCase(
            id: "rubric-err",
            suite: "s",
            task: "task",
            input: "input",
            rubric: RubricConfig(prompt: "Grade: {{result}}")
        )
        let useCase = RunCaseUseCase(adapter: adapter)
        let options = RunCaseUseCase.Options(
            evalCase: evalCase,
            resultSchemaPath: tempDir.appendingPathComponent("r.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rub.json"),
            artifactsDirectory: tempDir.appendingPathComponent("art"),
            provider: .claude,
            repoRoot: tempDir
        )

        let result = try await useCase.run(options)

        #expect(!result.passed)
        #expect(result.errors.contains(where: { $0.contains("rubric provider error") }))
    }

    // MARK: - Case ID Assembly

    @Test func caseIdIncludesSuiteAndId() async throws {
        let evalCase = EvalCase(id: "my-case", suite: "my-suite", task: "task", input: "input")
        let adapter = MockProviderAdapter(result: ProviderResult(provider: .claude, resultText: "ok"))
        let useCase = RunCaseUseCase(adapter: adapter)
        let options = RunCaseUseCase.Options(
            evalCase: evalCase,
            resultSchemaPath: tempDir.appendingPathComponent("r.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rub.json"),
            artifactsDirectory: tempDir.appendingPathComponent("art"),
            provider: .claude,
            repoRoot: tempDir
        )

        let result = try await useCase.run(options)

        #expect(result.caseId == "my-suite.my-case")
    }

    @Test func caseIdUsesUnknownWhenNoSuite() async throws {
        let evalCase = EvalCase(id: "orphan", task: "task", input: "input")
        let adapter = MockProviderAdapter(result: ProviderResult(provider: .claude, resultText: "ok"))
        let useCase = RunCaseUseCase(adapter: adapter)
        let options = RunCaseUseCase.Options(
            evalCase: evalCase,
            resultSchemaPath: tempDir.appendingPathComponent("r.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rub.json"),
            artifactsDirectory: tempDir.appendingPathComponent("art"),
            provider: .claude,
            repoRoot: tempDir
        )

        let result = try await useCase.run(options)

        #expect(result.caseId == "unknown.orphan")
    }

    // MARK: - Capability Gating

    @Test func toolEventChecksSkippedWhenNotSupported() async throws {
        let evalCase = EvalCase(
            id: "cap-1",
            suite: "s",
            task: "task",
            input: "input",
            deterministic: DeterministicChecks(traceCommandContains: ["grep"])
        )
        let adapter = MockProviderAdapter(
            capabilities: ProviderCapabilities(supportsToolEventAssertions: false),
            result: ProviderResult(provider: .claude, resultText: "ok")
        )
        let useCase = RunCaseUseCase(adapter: adapter)
        let options = RunCaseUseCase.Options(
            evalCase: evalCase,
            resultSchemaPath: tempDir.appendingPathComponent("r.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rub.json"),
            artifactsDirectory: tempDir.appendingPathComponent("art"),
            provider: .claude,
            repoRoot: tempDir
        )

        let result = try await useCase.run(options)

        #expect(result.passed)
        #expect(!result.skipped.isEmpty)
    }
}
