import AIOutputSDK
import EvalFeature
import EvalSDK
import EvalService
import Foundation
import ProviderRegistryService

@MainActor @Observable
final class EvalRunnerModel {

    enum State {
        case idle(prior: [EvalSummary])
        case running(progress: RunProgress, prior: [EvalSummary])
        case completed([EvalSummary])
        case error(Error, prior: [EvalSummary])

        var lastResults: [EvalSummary] {
            switch self {
            case .idle(let prior): return prior
            case .running(_, let prior): return prior
            case .completed(let summaries): return summaries
            case .error(_, let prior): return prior
            }
        }
    }

    struct RunProgress {
        var completedCases: Int
        var totalCases: Int
        var provider: String
        var currentCaseId: String?
        var currentTask: String?
        var currentOutput: String = ""
    }

    var state: State = .idle(prior: [])

    var suites: [EvalSuite] = []
    var selectedSuite: EvalSuite?
    var displayedCases: [EvalCase] = []

    let evalConfig: RepositoryEvalConfig
    let registry: EvalProviderRegistry

    private let clearArtifacts: ClearArtifactsUseCase
    private let gitClient: GitClient
    private let listSuites: ListEvalSuitesUseCase
    private let loadLastResults: LoadLastResultsUseCase
    private let readCaseOutput: ReadCaseOutputUseCase
    private let runEvals: RunEvalsUseCase

    init(
        config: RepositoryEvalConfig,
        skillName: String? = nil,
        registry: EvalProviderRegistry,
        clearArtifacts: ClearArtifactsUseCase = ClearArtifactsUseCase(),
        gitClient: GitClient = GitClient(),
        listSuites: ListEvalSuitesUseCase = ListEvalSuitesUseCase(),
        loadLastResults: LoadLastResultsUseCase = LoadLastResultsUseCase(),
        readCaseOutput: ReadCaseOutputUseCase = ReadCaseOutputUseCase()
    ) {
        self.evalConfig = config
        self.registry = registry
        self.clearArtifacts = clearArtifacts
        self.gitClient = gitClient
        self.listSuites = listSuites
        self.loadLastResults = loadLastResults
        self.readCaseOutput = readCaseOutput
        self.runEvals = RunEvalsUseCase(registry: registry)

        let options = ListEvalSuitesUseCase.Options(
            casesDirectory: config.casesDirectory,
            skillName: skillName
        )
        do {
            let loadedSuites = try listSuites.run(options)
            suites = loadedSuites
            if loadedSuites.count == 1 {
                selectedSuite = loadedSuites[0]
            }
        } catch {
            state = .error(error, prior: [])
        }
        filterCases()
        reloadLastResults()
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
        try gitClient.hasOutstandingChanges(at: evalConfig.repoRoot)
    }

    func run(
        providerFilter: [String]? = nil,
        suite: EvalSuite? = nil,
        evalCase: EvalCase? = nil
    ) async {
        let prior = state.lastResults
        let suiteName = suite?.name
        let caseId = evalCase?.id
        state = .running(progress: RunProgress(
            completedCases: 0,
            totalCases: 0,
            provider: providerFilter?.first ?? registry.defaultEntry?.name ?? "",
            currentCaseId: caseId
        ), prior: prior)

        let options = RunEvalsUseCase.Options(
            casesDirectory: evalConfig.casesDirectory,
            outputDirectory: evalConfig.outputDirectory,
            caseId: caseId,
            suite: suiteName,
            providerFilter: providerFilter,
            repoRoot: evalConfig.repoRoot
        )

        do {
            let summaries = try await runEvals.run(options) { [weak self] progress in
                guard let self else { return }
                Task { @MainActor in
                    switch progress {
                    case .startingProvider(let provider, let caseCount):
                        if case .running(var current, let prior) = self.state {
                            current.completedCases = 0
                            current.totalCases = caseCount
                            current.provider = provider
                            self.state = .running(progress: current, prior: prior)
                        }
                    case .startingCase(let caseId, _, let total, let provider, let task):
                        if case .running(var current, let prior) = self.state {
                            current.currentCaseId = caseId
                            current.currentTask = task
                            current.totalCases = total
                            current.provider = provider
                            current.currentOutput = ""
                            self.state = .running(progress: current, prior: prior)
                        }
                    case .caseOutput(_, let text):
                        if case .running(var current, let prior) = self.state {
                            current.currentOutput += text
                            self.state = .running(progress: current, prior: prior)
                        }
                    case .completedCase(let result, let index, let total, let provider):
                        if case .running(var current, let prior) = self.state {
                            current.completedCases = index + 1
                            current.totalCases = total
                            current.provider = provider
                            current.currentCaseId = result.caseId
                            current.currentOutput = ""
                            self.state = .running(progress: current, prior: prior)
                        }
                    case .completedProvider:
                        break
                    }
                }
            }

            if summaries.isEmpty {
                state = .error(EvalRunnerError.noCasesFound, prior: prior)
            } else {
                state = .completed(summaries)
            }
        } catch {
            state = .error(error, prior: prior)
        }
    }

    func reset() {
        state = .idle(prior: state.lastResults)
    }

    func clearAllArtifacts() {
        do {
            try clearArtifacts.run(outputDirectory: evalConfig.outputDirectory)
            state = .idle(prior: [])
        } catch {
            state = .error(error, prior: state.lastResults)
        }
    }

    func lastCaseResults(for evalCase: EvalCase) -> [(provider: String, result: CaseResult)] {
        let qualifiedId = evalCase.qualifiedId
        return state.lastResults.compactMap { summary in
            guard let result = summary.cases.first(where: {
                $0.caseId == qualifiedId || $0.caseId == evalCase.id || $0.caseId.hasSuffix(".\(evalCase.id)")
            }) else { return nil }
            return (summary.provider, result)
        }
    }

    func loadCaseOutput(for evalCase: EvalCase, provider: String) -> FormattedOutput? {
        let providerValue = Provider(rawValue: provider)

        let qualifiedId: String
        if let matchedResult = state.lastResults
            .flatMap(\.cases)
            .first(where: { $0.caseId == evalCase.qualifiedId || $0.caseId == evalCase.id || $0.caseId.hasSuffix(".\(evalCase.id)") }) {
            qualifiedId = matchedResult.caseId
        } else {
            qualifiedId = evalCase.qualifiedId
        }

        let entry = registry.entries.first(where: { $0.name == provider })
        guard let formatter = entry?.client.streamFormatter
                ?? registry.defaultEntry?.client.streamFormatter else {
            return nil
        }
        let rubricFormatter = entry?.client.streamFormatter
            ?? registry.defaultEntry?.client.streamFormatter ?? formatter

        let options = ReadCaseOutputUseCase.Options(
            caseId: qualifiedId,
            formatter: formatter,
            provider: providerValue,
            outputDirectory: evalConfig.outputDirectory,
            rubricFormatter: rubricFormatter
        )
        return try? readCaseOutput.run(options)
    }

    private func reloadLastResults() {
        let options = LoadLastResultsUseCase.Options(
            outputDirectory: evalConfig.outputDirectory,
            providerNames: registry.entries.map(\.name)
        )
        let summaries = loadLastResults.run(options)
        if !summaries.isEmpty {
            state = .idle(prior: summaries)
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
