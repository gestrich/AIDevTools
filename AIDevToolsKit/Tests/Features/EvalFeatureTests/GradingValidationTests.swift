import Testing
import Foundation
@testable import EvalFeature
@testable import EvalService
@testable import EvalSDK

// Validates that the eval framework correctly detects both passing AND failing cases
// across all grading capabilities. Each capability has a positive test (should pass)
// and a negative test (should fail with specific error).

@Suite("Grading Validation — Output Matching")
struct OutputMatchingValidation {

    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("GradingValidation-\(UUID().uuidString)")

    func makeOptions(_ evalCase: EvalCase) -> RunCaseUseCase.Options {
        RunCaseUseCase.Options(
            evalCase: evalCase,
            resultSchemaPath: tempDir.appendingPathComponent("r.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rub.json"),
            artifactsDirectory: tempDir.appendingPathComponent("art"),
            provider: Provider(rawValue: "claude"),
            repoRoot: tempDir
        )
    }

    // MARK: - Exact Match

    @Test func exactMatchPositive() async throws {
        let evalCase = EvalCase(
            id: "exact-pos", suite: "validation", task: "Add header", input: "code",
            expected: "// Copyright © Acme Corp, LLC. All rights reserved.\n\nimport Foundation"
        )
        let adapter = MockProviderAdapter(result: ProviderResult(
            provider: Provider(rawValue: "claude"),
            resultText: "// Copyright © Acme Corp, LLC. All rights reserved.\n\nimport Foundation"
        ))
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(result.passed)
        #expect(result.errors.isEmpty)
    }

    @Test func exactMatchNegative() async throws {
        let evalCase = EvalCase(
            id: "exact-neg", suite: "validation", task: "Add header", input: "code",
            expected: "// Copyright © Acme Corp, LLC. All rights reserved.\n\nimport Foundation"
        )
        let adapter = MockProviderAdapter(result: ProviderResult(
            provider: Provider(rawValue: "claude"),
            resultText: "// Wrong header\n\nimport Foundation"
        ))
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(!result.passed, "Should fail when output doesn't match expected")
        #expect(result.errors.contains(where: { $0.contains("exact output mismatch") }))
    }

    // MARK: - Must Include

    @Test func mustIncludePositive() async throws {
        let evalCase = EvalCase(
            id: "mi-pos", suite: "validation", task: "Add header", input: "code",
            mustInclude: ["Copyright", "Acme Corp"]
        )
        let adapter = MockProviderAdapter(result: ProviderResult(
            provider: Provider(rawValue: "claude"),
            resultText: "// Copyright © Acme Corp, LLC. All rights reserved."
        ))
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(result.passed)
    }

    @Test func mustIncludeNegative() async throws {
        let evalCase = EvalCase(
            id: "mi-neg", suite: "validation", task: "Add header", input: "code",
            mustInclude: ["Copyright", "Acme Corp"]
        )
        let adapter = MockProviderAdapter(result: ProviderResult(
            provider: Provider(rawValue: "claude"),
            resultText: "// Some other header with no relevant keywords"
        ))
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(!result.passed, "Should fail when required substrings are missing")
        #expect(result.errors.contains(where: { $0.contains("missing required substring: 'Copyright'") }))
        #expect(result.errors.contains(where: { $0.contains("missing required substring: 'Acme Corp'") }))
    }

    // MARK: - Must Not Include

    @Test func mustNotIncludePositive() async throws {
        let evalCase = EvalCase(
            id: "mni-pos", suite: "validation", task: "Add header", input: "code",
            mustNotInclude: ["TODO", "FIXME"]
        )
        let adapter = MockProviderAdapter(result: ProviderResult(
            provider: Provider(rawValue: "claude"),
            resultText: "// Copyright © Acme Corp, LLC."
        ))
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(result.passed)
    }

    @Test func mustNotIncludeNegative() async throws {
        let evalCase = EvalCase(
            id: "mni-neg", suite: "validation", task: "Add header", input: "code",
            mustNotInclude: ["TODO", "FIXME"]
        )
        let adapter = MockProviderAdapter(result: ProviderResult(
            provider: Provider(rawValue: "claude"),
            resultText: "// TODO: Add copyright header\n// FIXME: wrong format"
        ))
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(!result.passed, "Should fail when forbidden substrings are found")
        #expect(result.errors.contains(where: { $0.contains("found forbidden substring: 'TODO'") }))
        #expect(result.errors.contains(where: { $0.contains("found forbidden substring: 'FIXME'") }))
    }
}

@Suite("Grading Validation — Tool Event Assertions")
struct ToolEventValidation {

    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ToolEventValidation-\(UUID().uuidString)")

    func makeOptions(_ evalCase: EvalCase) -> RunCaseUseCase.Options {
        RunCaseUseCase.Options(
            evalCase: evalCase,
            resultSchemaPath: tempDir.appendingPathComponent("r.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rub.json"),
            artifactsDirectory: tempDir.appendingPathComponent("art"),
            provider: Provider(rawValue: "claude"),
            repoRoot: tempDir
        )
    }

    // MARK: - Trace Command Contains

    @Test func traceCommandContainsPositive() async throws {
        let evalCase = EvalCase(
            id: "tc-pos", suite: "validation", task: "task", input: "input",
            deterministic: DeterministicChecks(traceCommandContains: ["cat", "sed"])
        )
        let adapter = MockProviderAdapter(
            capabilities: ProviderCapabilities(supportsToolEventAssertions: true),
            result: ProviderResult(
                provider: Provider(rawValue: "claude"),
                resultText: "ok",
                toolEvents: [
                    ToolEvent(name: "bash", command: "cat file.swift"),
                    ToolEvent(name: "bash", command: "sed -i '' '1i\\// header' file.swift")
                ]
            )
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(result.passed)
    }

    @Test func traceCommandContainsNegative() async throws {
        let evalCase = EvalCase(
            id: "tc-neg", suite: "validation", task: "task", input: "input",
            deterministic: DeterministicChecks(traceCommandContains: ["cat", "sed"])
        )
        let adapter = MockProviderAdapter(
            capabilities: ProviderCapabilities(supportsToolEventAssertions: true),
            result: ProviderResult(
                provider: Provider(rawValue: "claude"),
                resultText: "ok",
                toolEvents: [
                    ToolEvent(name: "bash", command: "echo hello")
                ]
            )
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(!result.passed, "Should fail when required trace commands are missing")
        #expect(result.errors.contains(where: { $0.contains("missing trace command substring: 'cat'") }))
    }

    // MARK: - Trace Command Not Contains

    @Test func traceCommandNotContainsPositive() async throws {
        let evalCase = EvalCase(
            id: "tnc-pos", suite: "validation", task: "task", input: "input",
            deterministic: DeterministicChecks(traceCommandNotContains: ["rm -rf", "sudo"])
        )
        let adapter = MockProviderAdapter(
            capabilities: ProviderCapabilities(supportsToolEventAssertions: true),
            result: ProviderResult(
                provider: Provider(rawValue: "claude"),
                resultText: "ok",
                toolEvents: [ToolEvent(name: "bash", command: "cat file.swift")]
            )
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(result.passed)
    }

    @Test func traceCommandNotContainsNegative() async throws {
        let evalCase = EvalCase(
            id: "tnc-neg", suite: "validation", task: "task", input: "input",
            deterministic: DeterministicChecks(traceCommandNotContains: ["rm -rf"])
        )
        let adapter = MockProviderAdapter(
            capabilities: ProviderCapabilities(supportsToolEventAssertions: true),
            result: ProviderResult(
                provider: Provider(rawValue: "claude"),
                resultText: "ok",
                toolEvents: [ToolEvent(name: "bash", command: "rm -rf /tmp/test")]
            )
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(!result.passed, "Should fail when forbidden trace command is found")
        #expect(result.errors.contains(where: { $0.contains("found forbidden trace command substring: 'rm -rf'") }))
    }

    // MARK: - Trace Command Order

    @Test func traceCommandOrderPositive() async throws {
        let evalCase = EvalCase(
            id: "to-pos", suite: "validation", task: "task", input: "input",
            deterministic: DeterministicChecks(traceCommandOrder: ["cat", "sed", "echo"])
        )
        let adapter = MockProviderAdapter(
            capabilities: ProviderCapabilities(supportsToolEventAssertions: true),
            result: ProviderResult(
                provider: Provider(rawValue: "claude"),
                resultText: "ok",
                toolEvents: [
                    ToolEvent(name: "bash", command: "cat file.swift"),
                    ToolEvent(name: "bash", command: "sed -i '' '1s/^/header/' file.swift"),
                    ToolEvent(name: "bash", command: "echo done")
                ]
            )
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(result.passed)
    }

    @Test func traceCommandOrderNegative() async throws {
        let evalCase = EvalCase(
            id: "to-neg", suite: "validation", task: "task", input: "input",
            deterministic: DeterministicChecks(traceCommandOrder: ["sed", "cat"])
        )
        let adapter = MockProviderAdapter(
            capabilities: ProviderCapabilities(supportsToolEventAssertions: true),
            result: ProviderResult(
                provider: Provider(rawValue: "claude"),
                resultText: "ok",
                toolEvents: [
                    ToolEvent(name: "bash", command: "cat file.swift"),
                    ToolEvent(name: "bash", command: "sed -i '' '1s/^/header/' file.swift")
                ]
            )
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(!result.passed, "Should fail when commands are in wrong order")
        #expect(result.errors.contains(where: { $0.contains("trace command order violation") }))
    }

    // MARK: - Max Commands

    @Test func maxCommandsPositive() async throws {
        let evalCase = EvalCase(
            id: "mc-pos", suite: "validation", task: "task", input: "input",
            deterministic: DeterministicChecks(maxCommands: 3)
        )
        let adapter = MockProviderAdapter(
            capabilities: ProviderCapabilities(supportsToolEventAssertions: true),
            result: ProviderResult(
                provider: Provider(rawValue: "claude"),
                resultText: "ok",
                toolEvents: [
                    ToolEvent(name: "bash", command: "cat"),
                    ToolEvent(name: "bash", command: "sed"),
                ]
            )
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(result.passed)
    }

    @Test func maxCommandsNegative() async throws {
        let evalCase = EvalCase(
            id: "mc-neg", suite: "validation", task: "task", input: "input",
            deterministic: DeterministicChecks(maxCommands: 2)
        )
        let adapter = MockProviderAdapter(
            capabilities: ProviderCapabilities(supportsToolEventAssertions: true),
            result: ProviderResult(
                provider: Provider(rawValue: "claude"),
                resultText: "ok",
                toolEvents: [
                    ToolEvent(name: "bash", command: "cat"),
                    ToolEvent(name: "bash", command: "grep"),
                    ToolEvent(name: "bash", command: "sed"),
                    ToolEvent(name: "bash", command: "echo"),
                ]
            )
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(!result.passed, "Should fail when too many commands are executed")
        #expect(result.errors.contains(where: { $0.contains("exceeded max commands: 4 > 2") }))
    }

    // MARK: - Thrashing Detection

    @Test func thrashingDetectionPositive() async throws {
        let evalCase = EvalCase(
            id: "th-pos", suite: "validation", task: "task", input: "input",
            deterministic: DeterministicChecks(maxRepeatedCommands: 2)
        )
        let adapter = MockProviderAdapter(
            capabilities: ProviderCapabilities(supportsToolEventAssertions: true),
            result: ProviderResult(
                provider: Provider(rawValue: "claude"),
                resultText: "ok",
                toolEvents: [
                    ToolEvent(name: "bash", command: "cat file.swift"),
                    ToolEvent(name: "bash", command: "cat file.swift"),
                    ToolEvent(name: "bash", command: "sed file.swift"),
                ]
            )
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(result.passed)
    }

    @Test func thrashingDetectionNegative() async throws {
        let evalCase = EvalCase(
            id: "th-neg", suite: "validation", task: "task", input: "input",
            deterministic: DeterministicChecks(maxRepeatedCommands: 2)
        )
        let adapter = MockProviderAdapter(
            capabilities: ProviderCapabilities(supportsToolEventAssertions: true),
            result: ProviderResult(
                provider: Provider(rawValue: "claude"),
                resultText: "ok",
                toolEvents: [
                    ToolEvent(name: "bash", command: "cat file.swift"),
                    ToolEvent(name: "bash", command: "cat file.swift"),
                    ToolEvent(name: "bash", command: "cat file.swift"),
                ]
            )
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(!result.passed, "Should fail when commands are repeated excessively")
        #expect(result.errors.contains(where: { $0.contains("thrashing detected") }))
    }

    // MARK: - Capability Gating

    @Test func toolEventsSkippedWhenProviderLacksSupport() async throws {
        let evalCase = EvalCase(
            id: "cap-skip", suite: "validation", task: "task", input: "input",
            deterministic: DeterministicChecks(
                traceCommandContains: ["cat"],
                maxCommands: 3,
                maxRepeatedCommands: 2
            )
        )
        let adapter = MockProviderAdapter(
            capabilities: ProviderCapabilities(supportsToolEventAssertions: false),
            result: ProviderResult(provider: Provider(rawValue: "claude"), resultText: "ok")
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(result.passed, "Should pass since tool assertions are skipped")
        #expect(!result.skipped.isEmpty, "Should report skipped checks")
    }
}

@Suite("Grading Validation — Rubric Grading")
struct RubricGradingValidation {

    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("RubricValidation-\(UUID().uuidString)")

    func makeOptions(_ evalCase: EvalCase) -> RunCaseUseCase.Options {
        RunCaseUseCase.Options(
            evalCase: evalCase,
            resultSchemaPath: tempDir.appendingPathComponent("r.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rub.json"),
            artifactsDirectory: tempDir.appendingPathComponent("art"),
            provider: Provider(rawValue: "claude"),
            repoRoot: tempDir
        )
    }

    @Test func rubricOverallPassPositive() async throws {
        var callCount = 0
        var adapter = MockProviderAdapter()
        adapter.runHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return ProviderResult(provider: Provider(rawValue: "claude"), resultText: "good output")
            }
            return ProviderResult(
                provider: Provider(rawValue: "claude"),
                structuredOutput: [
                    "overall_pass": .bool(true),
                    "score": .int(8),
                    "checks": .array([])
                ]
            )
        }
        let evalCase = EvalCase(
            id: "rub-pos", suite: "validation", task: "task", input: "input",
            rubric: RubricConfig(prompt: "Grade: {{result}}", requireOverallPass: true)
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(result.passed)
    }

    @Test func rubricOverallPassNegative() async throws {
        var callCount = 0
        var adapter = MockProviderAdapter()
        adapter.runHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return ProviderResult(provider: Provider(rawValue: "claude"), resultText: "bad output")
            }
            return ProviderResult(
                provider: Provider(rawValue: "claude"),
                structuredOutput: [
                    "overall_pass": .bool(false),
                    "score": .int(3),
                    "checks": .array([])
                ]
            )
        }
        let evalCase = EvalCase(
            id: "rub-neg", suite: "validation", task: "task", input: "input",
            rubric: RubricConfig(prompt: "Grade: {{result}}", requireOverallPass: true)
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(!result.passed, "Should fail when rubric overall_pass is false")
        #expect(result.errors.contains(where: { $0.contains("overall_pass") }))
    }

    @Test func rubricMinScorePositive() async throws {
        var callCount = 0
        var adapter = MockProviderAdapter()
        adapter.runHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return ProviderResult(provider: Provider(rawValue: "claude"), resultText: "output")
            }
            return ProviderResult(
                provider: Provider(rawValue: "claude"),
                structuredOutput: [
                    "overall_pass": .bool(true),
                    "score": .int(8),
                    "checks": .array([])
                ]
            )
        }
        let evalCase = EvalCase(
            id: "rms-pos", suite: "validation", task: "task", input: "input",
            rubric: RubricConfig(prompt: "Grade: {{result}}", minScore: 7)
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(result.passed)
    }

    @Test func rubricMinScoreNegative() async throws {
        var callCount = 0
        var adapter = MockProviderAdapter()
        adapter.runHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return ProviderResult(provider: Provider(rawValue: "claude"), resultText: "output")
            }
            return ProviderResult(
                provider: Provider(rawValue: "claude"),
                structuredOutput: [
                    "overall_pass": .bool(true),
                    "score": .int(3),
                    "checks": .array([])
                ]
            )
        }
        let evalCase = EvalCase(
            id: "rms-neg", suite: "validation", task: "task", input: "input",
            rubric: RubricConfig(prompt: "Grade: {{result}}", minScore: 7)
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(!result.passed, "Should fail when score is below minScore")
        #expect(result.errors.contains(where: { $0.contains("rubric score below threshold") }))
    }

    @Test func rubricRequiredCheckPositive() async throws {
        var callCount = 0
        var adapter = MockProviderAdapter()
        adapter.runHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return ProviderResult(provider: Provider(rawValue: "claude"), resultText: "output")
            }
            return ProviderResult(
                provider: Provider(rawValue: "claude"),
                structuredOutput: [
                    "overall_pass": .bool(true),
                    "score": .int(9),
                    "checks": .array([
                        .object(["id": .string("header-format"), "pass": .bool(true), "notes": .string("correct")]),
                        .object(["id": .string("blank-line"), "pass": .bool(true), "notes": .string("present")])
                    ])
                ]
            )
        }
        let evalCase = EvalCase(
            id: "rci-pos", suite: "validation", task: "task", input: "input",
            rubric: RubricConfig(
                prompt: "Grade: {{result}}",
                requiredCheckIds: ["header-format", "blank-line"]
            )
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(result.passed)
    }

    @Test func rubricRequiredCheckNegativeMissing() async throws {
        var callCount = 0
        var adapter = MockProviderAdapter()
        adapter.runHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return ProviderResult(provider: Provider(rawValue: "claude"), resultText: "output")
            }
            return ProviderResult(
                provider: Provider(rawValue: "claude"),
                structuredOutput: [
                    "overall_pass": .bool(true),
                    "score": .int(7),
                    "checks": .array([
                        .object(["id": .string("header-format"), "pass": .bool(true), "notes": .string("ok")])
                    ])
                ]
            )
        }
        let evalCase = EvalCase(
            id: "rci-miss", suite: "validation", task: "task", input: "input",
            rubric: RubricConfig(
                prompt: "Grade: {{result}}",
                requiredCheckIds: ["header-format", "blank-line"]
            )
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(!result.passed, "Should fail when required check is missing")
        #expect(result.errors.contains(where: { $0.contains("missing rubric check id: blank-line") }))
    }

    @Test func rubricRequiredCheckNegativeFailed() async throws {
        var callCount = 0
        var adapter = MockProviderAdapter()
        adapter.runHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return ProviderResult(provider: Provider(rawValue: "claude"), resultText: "output")
            }
            return ProviderResult(
                provider: Provider(rawValue: "claude"),
                structuredOutput: [
                    "overall_pass": .bool(true),
                    "score": .int(5),
                    "checks": .array([
                        .object(["id": .string("header-format"), "pass": .bool(false), "notes": .string("wrong format")])
                    ])
                ]
            )
        }
        let evalCase = EvalCase(
            id: "rci-fail", suite: "validation", task: "task", input: "input",
            rubric: RubricConfig(
                prompt: "Grade: {{result}}",
                requiredCheckIds: ["header-format"]
            )
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(!result.passed, "Should fail when required check fails")
        #expect(result.errors.contains(where: { $0.contains("rubric check failed: header-format") }))
    }
}

@Suite("Grading Validation — Provider Errors")
struct ProviderErrorValidation {

    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ProviderErrorValidation-\(UUID().uuidString)")

    func makeOptions(_ evalCase: EvalCase) -> RunCaseUseCase.Options {
        RunCaseUseCase.Options(
            evalCase: evalCase,
            resultSchemaPath: tempDir.appendingPathComponent("r.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rub.json"),
            artifactsDirectory: tempDir.appendingPathComponent("art"),
            provider: Provider(rawValue: "claude"),
            repoRoot: tempDir
        )
    }

    @Test func providerErrorCaptured() async throws {
        let evalCase = EvalCase(id: "pe-neg", suite: "validation", task: "task", input: "input")
        let adapter = MockProviderAdapter(result: ProviderResult(
            provider: Provider(rawValue: "claude"),
            error: ProviderError(message: "CLI exited with code 1")
        ))
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(!result.passed, "Should fail when provider errors")
        #expect(result.errors.contains(where: { $0.contains("provider error") }))
    }

    @Test func rubricProviderErrorCaptured() async throws {
        var callCount = 0
        var adapter = MockProviderAdapter()
        adapter.runHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return ProviderResult(provider: Provider(rawValue: "claude"), resultText: "output")
            }
            return ProviderResult(
                provider: Provider(rawValue: "claude"),
                error: ProviderError(message: "rubric CLI timeout")
            )
        }
        let evalCase = EvalCase(
            id: "rpe-neg", suite: "validation", task: "task", input: "input",
            rubric: RubricConfig(prompt: "Grade: {{result}}")
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(!result.passed, "Should fail when rubric provider errors")
        #expect(result.errors.contains(where: { $0.contains("rubric provider error") }))
    }
}

@Suite("Grading Validation — Combined Failures")
struct CombinedFailureValidation {

    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("CombinedValidation-\(UUID().uuidString)")

    func makeOptions(_ evalCase: EvalCase) -> RunCaseUseCase.Options {
        RunCaseUseCase.Options(
            evalCase: evalCase,
            resultSchemaPath: tempDir.appendingPathComponent("r.json"),
            rubricSchemaPath: tempDir.appendingPathComponent("rub.json"),
            artifactsDirectory: tempDir.appendingPathComponent("art"),
            provider: Provider(rawValue: "claude"),
            repoRoot: tempDir
        )
    }

    @Test func multipleFailuresAccumulated() async throws {
        let evalCase = EvalCase(
            id: "multi-fail", suite: "validation", task: "task", input: "input",
            expected: "correct output",
            mustInclude: ["Acme Corp"],
            mustNotInclude: ["TODO"]
        )
        let adapter = MockProviderAdapter(result: ProviderResult(
            provider: Provider(rawValue: "claude"),
            resultText: "TODO: wrong output"
        ))
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(!result.passed)
        #expect(result.errors.count >= 3, "Should accumulate errors from exact match, mustInclude, and mustNotInclude")
        #expect(result.errors.contains(where: { $0.contains("exact output mismatch") }))
        #expect(result.errors.contains(where: { $0.contains("missing required substring: 'Acme Corp'") }))
        #expect(result.errors.contains(where: { $0.contains("found forbidden substring: 'TODO'") }))
    }

    @Test func outputPassesButToolEventsFail() async throws {
        let evalCase = EvalCase(
            id: "mixed-fail", suite: "validation", task: "task", input: "input",
            mustInclude: ["Copyright"],
            deterministic: DeterministicChecks(
                traceCommandNotContains: ["rm -rf"],
                maxCommands: 2
            )
        )
        let adapter = MockProviderAdapter(
            capabilities: ProviderCapabilities(supportsToolEventAssertions: true),
            result: ProviderResult(
                provider: Provider(rawValue: "claude"),
                resultText: "// Copyright header",
                toolEvents: [
                    ToolEvent(name: "bash", command: "cat file"),
                    ToolEvent(name: "bash", command: "rm -rf /tmp"),
                    ToolEvent(name: "bash", command: "echo done"),
                ]
            )
        )
        let result = try await RunCaseUseCase(adapter: adapter).run(makeOptions(evalCase))
        #expect(!result.passed, "Output passes but tool events should fail")
        #expect(result.errors.contains(where: { $0.contains("found forbidden trace command substring") }))
        #expect(result.errors.contains(where: { $0.contains("exceeded max commands") }))
    }
}
