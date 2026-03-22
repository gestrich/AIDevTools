import Foundation
import EvalService
import EvalSDK
import SkillScannerSDK

public struct RunCaseUseCase: Sendable {

    public struct Options: Sendable {
        public let evalCase: EvalCase
        public let resultSchemaPath: URL
        public let rubricSchemaPath: URL
        public let artifactsDirectory: URL
        public let provider: Provider
        public let model: String?
        public let keepTraces: Bool
        public let repoRoot: URL
        public let skills: [SkillInfo]

        public init(
            evalCase: EvalCase,
            resultSchemaPath: URL,
            rubricSchemaPath: URL,
            artifactsDirectory: URL,
            provider: Provider,
            model: String? = nil,
            keepTraces: Bool = false,
            repoRoot: URL,
            skills: [SkillInfo] = []
        ) {
            self.evalCase = evalCase
            self.resultSchemaPath = resultSchemaPath
            self.rubricSchemaPath = rubricSchemaPath
            self.artifactsDirectory = artifactsDirectory
            self.provider = provider
            self.model = model
            self.keepTraces = keepTraces
            self.repoRoot = repoRoot
            self.skills = skills
        }
    }

    private let adapter: any ProviderAdapterProtocol
    private let promptBuilder: PromptBuilder
    private let deterministicGrader: DeterministicGrader
    private let rubricEvaluator: RubricEvaluator
    private let artifactWriter: ArtifactWriter

    public init(
        adapter: any ProviderAdapterProtocol,
        promptBuilder: PromptBuilder = PromptBuilder(),
        deterministicGrader: DeterministicGrader = DeterministicGrader(),
        rubricEvaluator: RubricEvaluator = RubricEvaluator(),
        artifactWriter: ArtifactWriter = ArtifactWriter()
    ) {
        self.adapter = adapter
        self.promptBuilder = promptBuilder
        self.deterministicGrader = deterministicGrader
        self.rubricEvaluator = rubricEvaluator
        self.artifactWriter = artifactWriter
    }

    public func run(_ options: Options, onOutput: (@Sendable (String) -> Void)? = nil) async throws -> CaseResult {
        let evalCase = options.evalCase
        let caseId = "\(evalCase.suite ?? "unknown").\(evalCase.id)"

        let prompt = try promptBuilder.buildPrimaryPrompt(for: evalCase)

        let configuration = RunConfiguration(
            prompt: prompt,
            outputSchemaPath: options.resultSchemaPath,
            artifactsDirectory: options.artifactsDirectory,
            provider: options.provider,
            caseId: caseId,
            model: options.model,
            workingDirectory: options.repoRoot,
            evalMode: evalCase.mode
        )
        let providerResult = try await adapter.run(configuration: configuration, onOutput: onOutput)

        if options.keepTraces && !providerResult.events.isEmpty {
            let tracesDirectory = options.artifactsDirectory.appendingPathComponent("traces")
            let traceContent = encodeEventsAsJSONL(providerResult.events)
            try artifactWriter.writeTrace(content: traceContent, caseId: caseId, to: tracesDirectory)
        }

        if let error = providerResult.error {
            return CaseResult(
                caseId: caseId,
                passed: false,
                errors: ["provider error: \(error.message)"],
                task: evalCase.task ?? evalCase.prompt,
                input: evalCase.input,
                expected: evalCase.expected,
                mustInclude: evalCase.mustInclude,
                mustNotInclude: evalCase.mustNotInclude,
                toolCallSummary: providerResult.toolCallSummary
            )
        }

        let resultText = providerResult.resultText ?? ""
        let traceCommands = providerResult.toolEvents.compactMap(\.command)
        let capabilities = adapter.capabilities()

        let skillChecks = resolveSkillChecks(
            evalCase: evalCase,
            toolEvents: providerResult.toolEvents,
            traceCommands: traceCommands,
            capabilities: capabilities,
            skills: options.skills,
            repoRoot: options.repoRoot
        )

        let gradeResult = deterministicGrader.grade(
            case: evalCase,
            resultText: resultText,
            traceCommands: traceCommands,
            toolEvents: providerResult.toolEvents,
            providerCapabilities: capabilities,
            skillChecks: skillChecks
        )

        var errors = gradeResult.errors
        let skipped = gradeResult.skipped

        if evalCase.mode != .edit, let rubric = evalCase.rubric {
            let rubricErrors = try await rubricEvaluator.evaluate(
                rubric: rubric,
                evalCase: evalCase,
                caseId: caseId,
                resultText: resultText,
                adapter: adapter,
                rubricSchemaPath: options.rubricSchemaPath,
                artifactsDirectory: options.artifactsDirectory,
                provider: options.provider,
                model: options.model,
                repoRoot: options.repoRoot
            )
            errors.append(contentsOf: rubricErrors)
        }

        return CaseResult(
            caseId: caseId,
            passed: errors.isEmpty,
            errors: errors,
            skipped: skipped,
            skillChecks: gradeResult.skillChecks,
            task: evalCase.task ?? evalCase.prompt,
            input: evalCase.input,
            expected: evalCase.expected,
            mustInclude: evalCase.mustInclude,
            mustNotInclude: evalCase.mustNotInclude,
            providerResponse: resultText,
            toolCallSummary: providerResult.toolCallSummary
        )
    }

    private func resolveSkillChecks(
        evalCase: EvalCase,
        toolEvents: [ToolEvent],
        traceCommands: [String],
        capabilities: ProviderCapabilities,
        skills: [SkillInfo],
        repoRoot: URL
    ) -> [SkillCheckResult] {
        var checks: [SkillCheckResult] = []

        for assertion in evalCase.skills ?? [] {
            let skillName = assertion.skill
            if !capabilities.supportsToolEventAssertions {
                checks.append(.skipped(skillName: skillName, reason: "provider lacks support"))
            } else {
                let method = adapter.invocationMethod(for: skillName, toolEvents: toolEvents, traceCommands: traceCommands, skills: skills, repoRoot: repoRoot)
                if let method {
                    let skill = skills.first(where: { $0.name == skillName }) ?? SkillInfo(name: skillName, path: URL(fileURLWithPath: skillName))
                    checks.append(.invoked(skill, method: method))
                } else {
                    checks.append(.notInvoked(skillName: skillName))
                }
            }
        }

        return checks
    }

    private func encodeEventsAsJSONL(_ events: [[String: JSONValue]]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return events.compactMap { event in
            guard let data = try? encoder.encode(event),
                  let line = String(data: data, encoding: .utf8) else { return nil }
            return line
        }.joined(separator: "\n")
    }
}
