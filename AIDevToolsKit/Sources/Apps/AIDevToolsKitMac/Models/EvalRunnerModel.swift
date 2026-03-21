import EvalFeature
import EvalSDK
import EvalService
import Foundation

private let debugLogURL: URL = {
    let url = URL(fileURLWithPath: "/tmp/eval_runner_debug.log")
    try? "".write(to: url, atomically: true, encoding: .utf8)
    return url
}()

private func debugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    if let data = line.data(using: .utf8),
       let handle = try? FileHandle(forWritingTo: debugLogURL) {
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
    }
}

@MainActor @Observable
final class EvalRunnerModel {

    enum State {
        case idle
        case running(progress: RunProgress)
        case completed([EvalSummary])
        case error(Error)
    }

    struct RunProgress {
        var completedCases: Int
        var totalCases: Int
        var provider: String
        var currentCaseId: String?
        var currentTask: String?
        var currentOutput: String = ""
    }

    var state: State = .idle
    var lastResults: [EvalSummary] = []

    var suites: [EvalSuite] = []
    var selectedSuite: EvalSuite?
    var displayedCases: [EvalCase] = []

    private(set) var evalConfig: RepositoryEvalConfig?

    private let runEvals: RunEvalsUseCase
    private let listSuites: ListEvalSuitesUseCase

    init(
        runEvals: RunEvalsUseCase = RunEvalsUseCase(),
        listSuites: ListEvalSuitesUseCase = ListEvalSuitesUseCase()
    ) {
        self.runEvals = runEvals
        self.listSuites = listSuites
    }

    func configure(with config: RepositoryEvalConfig?) {
        evalConfig = config
        suites = []
        selectedSuite = nil
        displayedCases = []
        lastResults = []
        state = .idle
    }

    func loadSuites(skillName: String?) {
        guard let casesDirectory = evalConfig?.casesDirectory else { return }
        let options = ListEvalSuitesUseCase.Options(
            casesDirectory: casesDirectory,
            skillName: skillName
        )
        guard let loadedSuites = try? listSuites.run(options) else { return }

        suites = loadedSuites
        if suites.count == 1 {
            selectedSuite = suites[0]
        }
        filterCases()
        loadLastResults()
    }

    func selectSuite(_ suite: EvalSuite?) {
        selectedSuite = suite
        filterCases()
    }

    private func filterCases() {
        if let selected = selectedSuite {
            displayedCases = selected.cases
        } else {
            displayedCases = suites.flatMap(\.cases)
        }
    }

    func hasEditCases(suite: EvalSuite? = nil, evalCase: EvalCase? = nil) -> Bool {
        if let evalCase {
            return evalCase.mode == .edit
        } else if let suite {
            return suite.cases.contains { $0.mode == .edit }
        }
        return displayedCases.contains { $0.mode == .edit }
    }

    func repoHasOutstandingChanges() throws -> Bool {
        guard let evalConfig else { return false }
        return try GitClient().hasOutstandingChanges(at: evalConfig.repoRoot)
    }

    func run(
        providers: [Provider],
        suite: EvalSuite? = nil,
        evalCase: EvalCase? = nil
    ) async {
        guard let evalConfig else { return }
        let suiteName = suite?.name
        let caseId = evalCase?.id
        debugLog("run() called — providers=\(providers.map(\.rawValue)), suite=\(suiteName ?? "nil"), caseId=\(caseId ?? "nil")")
        state = .running(progress: RunProgress(
            completedCases: 0,
            totalCases: 0,
            provider: providers.first?.rawValue ?? "",
            currentCaseId: caseId
        ))
        debugLog("state -> .running (initial)")

        let options = RunEvalsUseCase.Options(
            casesDirectory: evalConfig.casesDirectory,
            outputDirectory: evalConfig.outputDirectory,
            caseId: caseId,
            suite: suiteName,
            providers: providers,
            repoRoot: evalConfig.repoRoot
        )

        do {
            debugLog("calling runEvals.run()...")
            let summaries = try await runEvals.run(options) { [weak self] progress in
                guard let self else { return }
                Task { @MainActor in
                    let priorState = "\(self.state)"
                    switch progress {
                    case .startingProvider(let provider, let caseCount):
                        debugLog("progress: startingProvider(\(provider), count=\(caseCount)) | state=\(priorState)")
                        if case .running(var current) = self.state {
                            current.completedCases = 0
                            current.totalCases = caseCount
                            current.provider = provider
                            self.state = .running(progress: current)
                        }
                    case .startingCase(let caseId, _, let total, let provider, let task):
                        debugLog("progress: startingCase(\(caseId), provider=\(provider)) | state=\(priorState)")
                        if case .running(var current) = self.state {
                            current.currentCaseId = caseId
                            current.currentTask = task
                            current.totalCases = total
                            current.provider = provider
                            current.currentOutput = ""
                            self.state = .running(progress: current)
                        }
                    case .caseOutput(let caseId, let text):
                        debugLog("progress: caseOutput(\(caseId), len=\(text.count)) | state=\(priorState)")
                        if case .running(var current) = self.state {
                            current.currentOutput += text
                            self.state = .running(progress: current)
                        }
                    case .completedCase(let result, let index, let total, let provider):
                        debugLog("progress: completedCase(\(result.caseId), \(index)/\(total), passed=\(result.passed)) | state=\(priorState)")
                        if case .running(var current) = self.state {
                            current.completedCases = index + 1
                            current.totalCases = total
                            current.provider = provider
                            current.currentCaseId = result.caseId
                            current.currentOutput = ""
                            self.state = .running(progress: current)
                        }
                    case .completedProvider:
                        debugLog("progress: completedProvider | state=\(priorState)")
                        break
                    }
                }
            }

            debugLog("runEvals.run() returned \(summaries.count) summaries")
            for s in summaries {
                debugLog("  summary: provider=\(s.provider), total=\(s.total), passed=\(s.passed), failed=\(s.failed)")
            }
            if summaries.isEmpty {
                debugLog("state -> .error(noCasesFound)")
                state = .error(EvalRunnerError.noCasesFound)
            } else {
                debugLog("state -> .completed(\(summaries.count) summaries)")
                lastResults = summaries
                state = .completed(summaries)
            }
        } catch {
            debugLog("state -> .error(\(error))")
            state = .error(error)
        }
    }

    func reset() {
        state = .idle
    }

    func clearArtifacts() {
        guard let outputDirectory = evalConfig?.outputDirectory else { return }
        do {
            try ClearArtifactsUseCase().run(outputDirectory: outputDirectory)
            lastResults = []
            state = .idle
        } catch {
            state = .error(error)
        }
    }

    func lastCaseResults(for evalCase: EvalCase) -> [(provider: String, result: CaseResult)] {
        let qualifiedId = evalCase.qualifiedId
        return lastResults.compactMap { summary in
            guard let result = summary.cases.first(where: {
                $0.caseId == qualifiedId || $0.caseId == evalCase.id || $0.caseId.hasSuffix(".\(evalCase.id)")
            }) else { return nil }
            return (summary.provider, result)
        }
    }

    func loadCaseOutput(for evalCase: EvalCase, provider: String) -> FormattedOutput? {
        guard let evalConfig,
              let providerEnum = Provider(rawValue: provider) else { return nil }

        let qualifiedId: String
        if let matchedResult = lastResults
            .flatMap(\.cases)
            .first(where: { $0.caseId == evalCase.qualifiedId || $0.caseId == evalCase.id || $0.caseId.hasSuffix(".\(evalCase.id)") }) {
            qualifiedId = matchedResult.caseId
        } else {
            qualifiedId = evalCase.qualifiedId
        }

        let options = ReadCaseOutputUseCase.Options(
            caseId: qualifiedId,
            provider: providerEnum,
            outputDirectory: evalConfig.outputDirectory
        )
        return try? ReadCaseOutputUseCase().run(options)
    }

    func loadLastResults() {
        guard let outputDirectory = evalConfig?.outputDirectory else { return }
        let artifactsDir = outputDirectory.appendingPathComponent("artifacts")
        let fm = FileManager.default
        guard fm.fileExists(atPath: artifactsDir.path) else { return }

        let decoder = JSONDecoder()
        var summaries: [EvalSummary] = []

        for provider in Provider.allCases {
            let summaryFile = artifactsDir
                .appendingPathComponent(provider.rawValue)
                .appendingPathComponent("summary.json")
            guard let data = try? Data(contentsOf: summaryFile),
                  let summary = try? decoder.decode(EvalSummary.self, from: data) else {
                continue
            }
            summaries.append(summary)
        }

        if !summaries.isEmpty {
            lastResults = summaries
        }
    }
}

enum EvalRunnerError: LocalizedError {
    case noCasesFound

    var errorDescription: String? {
        switch self {
        case .noCasesFound: return "No eval cases found matching filters."
        }
    }
}
