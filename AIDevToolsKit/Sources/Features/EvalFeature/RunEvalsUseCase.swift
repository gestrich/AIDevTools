import Foundation
import EvalService
import EvalSDK
import SkillScannerSDK

public struct RunEvalsUseCase: Sendable {

    public struct Options: Sendable {
        public let casesDirectory: URL
        public let outputDirectory: URL
        public let caseId: String?
        public let suite: String?
        public let providers: [Provider]
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
            providers: [Provider],
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
            self.providers = providers
            self.resultSchemaPath = resultSchemaPath
            self.rubricSchemaPath = rubricSchemaPath
            self.model = model
            self.keepTraces = keepTraces
            self.debug = debug
            self.repoRoot = repoRoot
        }
    }

    public struct ProviderEntry: Sendable {
        public let provider: Provider
        public let adapter: any ProviderAdapterProtocol

        public init(provider: Provider, adapter: any ProviderAdapterProtocol) {
            self.provider = provider
            self.adapter = adapter
        }
    }

    private let overrideEntries: [ProviderEntry]?
    private let caseLoader: CaseLoader
    private let gitClient: GitClient
    private let deterministicGrader: DeterministicGrader
    private let rubricEvaluator: RubricEvaluator

    public init(
        caseLoader: CaseLoader = CaseLoader(),
        gitClient: GitClient = GitClient(),
        deterministicGrader: DeterministicGrader = DeterministicGrader(),
        rubricEvaluator: RubricEvaluator = RubricEvaluator()
    ) {
        self.overrideEntries = nil
        self.caseLoader = caseLoader
        self.gitClient = gitClient
        self.deterministicGrader = deterministicGrader
        self.rubricEvaluator = rubricEvaluator
    }

    public init(
        providers: [ProviderEntry],
        caseLoader: CaseLoader = CaseLoader(),
        gitClient: GitClient = GitClient(),
        deterministicGrader: DeterministicGrader = DeterministicGrader(),
        rubricEvaluator: RubricEvaluator = RubricEvaluator()
    ) {
        self.overrideEntries = providers
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

        let entries = overrideEntries ?? options.providers.map { provider in
            ProviderEntry(provider: provider, adapter: makeAdapter(for: provider, debug: options.debug))
        }

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

    private func makeAdapter(for provider: Provider, debug: Bool = false) -> any ProviderAdapterProtocol {
        switch provider {
        case .codex: return CodexAdapter()
        case .claude: return ClaudeAdapter(debug: debug)
        }
    }

    private func runProvider(
        entry: ProviderEntry,
        artifactsDirectory: URL,
        cases: [EvalCase],
        resultSchemaPath: URL,
        rubricSchemaPath: URL,
        options: Options,
        skills: [SkillInfo],
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> EvalSummary {
        let runCase = RunCaseUseCase(adapter: entry.adapter)
        var results: [CaseResult] = []
        let providerName = entry.provider.rawValue

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
                let warning = "⚠ \(summary.rejected) tool call(s) rejected (permissions)"
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
                        adapter: entry.adapter,
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
