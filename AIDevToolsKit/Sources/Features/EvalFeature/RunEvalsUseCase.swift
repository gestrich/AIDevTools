import AIOutputSDK
import EvalSDK
import EvalService
import Foundation
import ProviderRegistryService
import SkillScannerSDK
import UseCaseSDK

public struct RunEvalsUseCase: UseCase {

    public struct Options: Sendable {
        public let casesDirectory: URL
        public let outputDirectory: URL
        public let caseId: String?
        public let suite: String?
        public let providerFilter: [String]?
        public let resultSchemaPath: URL?
        public let rubricSchemaPath: URL?
        public let model: String?
        public let keepTraces: Bool
        public let debug: Bool
        public let repoRoot: URL

        public init(
            casesDirectory: URL,
            outputDirectory: URL,
            caseId: String? = nil,
            suite: String? = nil,
            providerFilter: [String]? = nil,
            resultSchemaPath: URL? = nil,
            rubricSchemaPath: URL? = nil,
            model: String? = nil,
            keepTraces: Bool = false,
            debug: Bool = false,
            repoRoot: URL
        ) {
            self.casesDirectory = casesDirectory
            self.outputDirectory = outputDirectory
            self.caseId = caseId
            self.suite = suite
            self.providerFilter = providerFilter
            self.resultSchemaPath = resultSchemaPath
            self.rubricSchemaPath = rubricSchemaPath
            self.model = model
            self.keepTraces = keepTraces
            self.debug = debug
            self.repoRoot = repoRoot
        }
    }

    private let registry: EvalProviderRegistry
    private let caseLoader: CaseLoader
    private let gitClient: GitClient
    private let deterministicGrader: DeterministicGrader
    private let rubricEvaluator: RubricEvaluator

    public init(
        registry: EvalProviderRegistry,
        caseLoader: CaseLoader = CaseLoader(),
        gitClient: GitClient = GitClient(),
        deterministicGrader: DeterministicGrader = DeterministicGrader(),
        rubricEvaluator: RubricEvaluator = RubricEvaluator()
    ) {
        self.registry = registry
        self.caseLoader = caseLoader
        self.gitClient = gitClient
        self.deterministicGrader = deterministicGrader
        self.rubricEvaluator = rubricEvaluator
    }

    public enum Progress: Sendable {
        case startingProvider(provider: String, caseCount: Int)
        case startingCase(caseId: String, index: Int, total: Int, provider: String, task: String?)
        case caseOutput(caseId: String, text: String)
        case completedCase(result: CaseResult, index: Int, total: Int, provider: String)
        case completedProvider(summary: EvalSummary)
    }

    public func run(
        _ options: Options,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> [EvalSummary] {
        let casesDir = options.casesDirectory.appendingPathComponent("cases")
        var cases = try caseLoader.loadCases(from: casesDir)
        cases = caseLoader.filterCases(cases, caseId: options.caseId, suite: options.suite)

        guard !cases.isEmpty else {
            return []
        }

        let resultSchemaPath = options.resultSchemaPath
            ?? options.outputDirectory.appendingPathComponent("result_output_schema.json")
        let rubricSchemaPath = options.rubricSchemaPath
            ?? options.outputDirectory.appendingPathComponent("rubric_output_schema.json")
        let artifactsDir = options.outputDirectory.appendingPathComponent("artifacts")

        let skills = try SkillScanner().scanSkills(at: options.repoRoot)

        let entries = registry.filtered(by: options.providerFilter)

        var summaries: [EvalSummary] = []

        for entry in entries {
            let summary = try await runProvider(
                entry: entry,
                artifactsDirectory: artifactsDir,
                cases: cases,
                resultSchemaPath: resultSchemaPath,
                rubricSchemaPath: rubricSchemaPath,
                options: options,
                skills: skills,
                onProgress: onProgress
            )
            summaries.append(summary)
        }

        return summaries
    }

    private func gitReset(at repoRoot: URL) async throws {
        for arguments in [["reset", "--hard", "HEAD"], ["clean", "-ffdd"]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            process.currentDirectoryURL = repoRoot
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
        }
    }

    private func runProvider(
        entry: EvalProviderEntry,
        artifactsDirectory: URL,
        cases: [EvalCase],
        resultSchemaPath: URL,
        rubricSchemaPath: URL,
        options: Options,
        skills: [SkillInfo],
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> EvalSummary {
        let runCase = RunCaseUseCase(client: entry.client)
        var results: [CaseResult] = []
        let providerName = entry.name

        onProgress?(.startingProvider(provider: providerName, caseCount: cases.count))

        for (index, evalCase) in cases.enumerated() {
            let caseId = "\(evalCase.suite ?? "unknown").\(evalCase.id)"
            onProgress?(.startingCase(caseId: caseId, index: index, total: cases.count, provider: providerName, task: evalCase.task ?? evalCase.prompt))

            if evalCase.mode == .edit {
                try await gitReset(at: options.repoRoot)
            }

            let caseOptions = RunCaseUseCase.Options(
                evalCase: evalCase,
                resultSchemaPath: resultSchemaPath,
                rubricSchemaPath: rubricSchemaPath,
                artifactsDirectory: artifactsDirectory,
                provider: entry.provider,
                model: options.model,
                keepTraces: options.keepTraces,
                repoRoot: options.repoRoot,
                skills: skills
            )

            var result = try await runCase.run(caseOptions) { text in
                onProgress?(.caseOutput(caseId: caseId, text: text))
            }

            if let summary = result.toolCallSummary, summary.rejected > 0 {
                let warning = "\u{26A0} \(summary.rejected) tool call(s) rejected (permissions)"
                result.errors.append(warning)
            }

            if evalCase.mode == .edit {
                let diff = try gitClient.diff(at: options.repoRoot)

                let fileErrors = deterministicGrader.gradeFileChanges(
                    case: evalCase,
                    diff: diff,
                    repoRoot: options.repoRoot
                )
                result.errors.append(contentsOf: fileErrors)

                if let rubric = evalCase.rubric {
                    let rubricErrors = try await rubricEvaluator.evaluate(
                        rubric: rubric,
                        evalCase: evalCase,
                        caseId: caseId,
                        resultText: result.providerResponse ?? "",
                        client: entry.client,
                        rubricSchemaPath: rubricSchemaPath,
                        artifactsDirectory: artifactsDirectory,
                        provider: entry.provider,
                        model: options.model,
                        repoRoot: options.repoRoot
                    )
                    result.errors.append(contentsOf: rubricErrors)
                }

                result.passed = result.errors.isEmpty
            }

            results.append(result)

            if evalCase.mode == .edit {
                try await gitReset(at: options.repoRoot)
            }

            onProgress?(.completedCase(result: result, index: index, total: cases.count, provider: providerName))
        }

        let passed = results.filter { $0.passed && $0.skipped.isEmpty }.count
        let skippedCount = results.filter { !$0.skipped.isEmpty }.count
        let failed = results.filter { !$0.passed }.count

        let summary = EvalSummary(
            provider: providerName,
            total: results.count,
            passed: passed,
            failed: failed,
            skipped: skippedCount,
            cases: results
        )

        let outputService = OutputService()
        try outputService.writeSummary(summary, artifactsDirectory: artifactsDirectory, provider: entry.provider)

        onProgress?(.completedProvider(summary: summary))

        return summary
    }
}
