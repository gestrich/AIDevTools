import Foundation
import GitHubService
import Logging
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import PRReviewFeature

private let logger = Logger(label: "AllPRsModel")

@Observable
@MainActor
final class AllPRsModel {

    private(set) var state: State = .uninitialized
    private(set) var refreshAllState: RefreshAllState = .idle
    private(set) var analyzeAllState: AnalyzeAllState = .idle
    var showOnlyWithPendingComments: Bool = false

    let config: PRRadarRepoConfig
    private var gitHubPRService: (any GitHubPRServiceProtocol)?
    private var changesTask: Task<Void, Never>?

    init(config: PRRadarRepoConfig) {
        self.config = config
        Task { await loadCached() }
    }

    // MARK: - Cache Load

    func loadCached() async {
        state = .loading
        let models = applyMetadata(await cachedPRs(filter: config.makeFilter()))
        loadSummariesInBackground(for: models)
    }

    // MARK: - GitHub Refresh

    func refresh(number: Int) async throws -> PRModel? {
        let useCase = FetchPRUseCase(config: config)
        for try await progress in useCase.execute(prNumber: number, force: true) {
            switch progress {
            case .failed(let error, _):
                throw RefreshError.failed(error)
            default: break
            }
        }
        let models = applyMetadata(await cachedPRs(filter: config.makeFilter()))
        loadSummariesInBackground(for: models)
        return models.first(where: { $0.metadata.number == number })
    }

    func refresh(filter: PRFilter) async {
        let prior = currentPRModels
        self.state = .refreshing(prior ?? [])
        refreshAllState = .running(logs: "Fetching PR list from GitHub...\n", current: 0, total: 0)

        let useCase = FetchPRsUseCase(config: config)

        var updatedMetadata: [PRMetadata]?
        do {
            for try await progress in useCase.execute(filter: filter) {
                switch progress {
                case .running, .progress:
                    break
                case .log(let text):
                    appendRefreshLog(text)
                case .prepareOutput: break
                case .prepareToolUse: break
                case .taskEvent: break
                case .completed(let result):
                    updatedMetadata = result.prList
                    startObservingChanges(service: result.gitHubPRService)
                case .failed(let error, _):
                    logger.error("refresh() use case failed", metadata: ["error": "\(error)", "repo": "\(config.name)"])
                    self.state = .failed(error, prior: prior)
                    refreshAllState = .completed(logs: refreshAllLogs + "Failed: \(error)\n")
                    return
                }
            }
        } catch {
            logger.error("refresh() threw", metadata: ["error": "\(error.localizedDescription)", "repo": "\(config.name)"])
            self.state = .failed(error.localizedDescription, prior: prior)
            refreshAllState = .completed(logs: refreshAllLogs + "Failed: \(error.localizedDescription)\n")
            return
        }

        guard let metadata = updatedMetadata else {
            logger.warning("refresh() no metadata after use case completed", metadata: ["repo": "\(config.name)"])
            refreshAllState = .completed(logs: refreshAllLogs + "No PRs found.\n")
            return
        }

        var premergeUpdatedAt: [Int: String] = [:]
        for pr in prior ?? [] {
            if let updatedAt = pr.metadata.updatedAt {
                premergeUpdatedAt[pr.metadata.number] = updatedAt
            }
        }

        let mergedModels = applyMetadata(metadata)
        loadSummariesInBackground(for: mergedModels)

        let prsToRefresh = filteredPRs(mergedModels, filter: filter)
        let total = prsToRefresh.count
        appendRefreshLog("Found \(metadata.count) PRs, refreshing \(total)...\n")
        refreshAllState = .running(logs: refreshAllLogs, current: 0, total: total)

        for (index, pr) in prsToRefresh.enumerated() {
            let current = index + 1
            if let cachedAt = premergeUpdatedAt[pr.metadata.number],
               cachedAt == pr.metadata.updatedAt {
                logger.trace("PR unchanged, skipping refresh", metadata: ["pr": "\(pr.metadata.number)", "repo": "\(config.name)"])
                appendRefreshLog("[\(current)/\(total)] PR \(pr.metadata.displayNumber): unchanged\n")
                refreshAllState = .running(logs: refreshAllLogs, current: current, total: total)
                continue
            }
            appendRefreshLog("[\(current)/\(total)] PR \(pr.metadata.displayNumber): \(pr.metadata.title)\n")
            refreshAllState = .running(logs: refreshAllLogs, current: current, total: total)
            await pr.refreshPRData()
        }

        refreshAllState = .completed(logs: refreshAllLogs + "\nRefresh complete.\n")
    }

    func dismissRefreshAllState() {
        refreshAllState = .idle
    }

    // MARK: - Delete PR Data

    func deletePRData(for prModel: PRModel) async throws {
        let refreshedMetadata = try await DeletePRDataUseCase(config: config)
            .execute(prNumber: prModel.metadata.number)
        prModel.resetAfterDataDeletion(metadata: refreshedMetadata)
    }

    // MARK: - Analyze All

    func analyzeAll(filter: PRFilter, ruleFilePaths: [String]? = nil) async {
        guard let models = currentPRModels else { return }

        let prsToAnalyze = filteredPRs(models, filter: filter)
        let total = prsToAnalyze.count

        analyzeAllState = .running(logs: "Analyzing \(total) PRs...\n", current: 0, total: total)

        var analyzedCount = 0
        var failedCount = 0

        for (index, pr) in prsToAnalyze.enumerated() {
            let current = index + 1
            if case .running(let logs, _, _) = analyzeAllState {
                analyzeAllState = .running(
                    logs: logs + "[\(current)/\(total)] PR #\(pr.prNumber): \(pr.metadata.title)\n",
                    current: current,
                    total: total
                )
            }

            if await pr.runAnalysis(ruleFilePaths: ruleFilePaths) {
                analyzedCount += 1
            } else {
                failedCount += 1
            }
        }

        let logs = analyzeAllLogs
        analyzeAllState = .completed(
            logs: logs + "\nAnalyze-all complete: \(analyzedCount) succeeded, \(failedCount) failed\n"
        )
    }

    func dismissAnalyzeAllState() {
        analyzeAllState = .idle
    }

    // MARK: - Acquisition

    private func cachedPRs(filter: PRFilter? = nil) async -> [PRMetadata] {
        await CachedPRsUseCase(config: config).execute(filter: filter)
    }

    // MARK: - Reconciliation

    @discardableResult
    private func applyMetadata(_ metadata: [PRMetadata]) -> [PRModel] {
        let models = PRModel.make(from: metadata, reusingExisting: currentPRModels, config: config)
        state = .ready(models)
        return models
    }

    // MARK: - Enrichment

    private func loadSummariesInBackground(for models: [PRModel]) {
        logger.trace("Loading summaries for \(models.count) PRs", metadata: ["repo": "\(config.name)"])
        Task {
            await withTaskGroup(of: Void.self) { group in
                for model in models {
                    group.addTask {
                        await model.loadSummary()
                    }
                }
            }
            logger.trace("Finished loading summaries", metadata: ["repo": "\(config.name)"])
        }
    }

    // MARK: - Filtering

    func filteredPRModels(filter: PRFilter) -> [PRModel] {
        guard let models = currentPRModels else { return [] }
        return filteredPRs(models, filter: filter)
    }

    var availableAuthors: [AuthorOption] {
        guard let models = currentPRModels else { return [] }
        let prAuthors = models.map { AuthorOption(login: $0.metadata.author.login, name: $0.metadata.author.name) }
        let cache = AuthorCacheService().load()
        let cacheAuthors = cache.entries.values.map { AuthorOption(login: $0.login, name: $0.name) }
        var seen = Set<String>()
        var result: [AuthorOption] = []
        for author in prAuthors + cacheAuthors {
            if !author.login.isEmpty && seen.insert(author.login).inserted {
                result.append(author)
            }
        }
        return result.sorted { $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending }
    }

    func filteredPRs(_ models: [PRModel], filter: PRFilter = PRFilter()) -> [PRModel] {
        var result = models.filter { filter.matches($0.metadata) }
        if showOnlyWithPendingComments {
            result = result.filter { $0.hasPendingComments }
        }
        return result
    }

    // MARK: - Change Observation

    private func startObservingChanges(service: any GitHubPRServiceProtocol) {
        changesTask?.cancel()
        gitHubPRService = service
        changesTask = Task { [weak self] in
            for await prNumber in service.changes() {
                guard let self else { break }
                let updated = await CachedPRsUseCase(config: self.config).executeSingle(prNumber: prNumber)
                guard let updated else { continue }
                if let model = self.currentPRModels?.first(where: { $0.prNumber == prNumber }) {
                    model.updateMetadata(updated)
                    await model.loadSummary()
                }
            }
        }
    }

    // MARK: - Helpers

    var currentPRModels: [PRModel]? {
        switch state {
        case .ready(let models): return models
        case .refreshing(let models): return models
        case .failed(_, let prior): return prior
        default: return nil
        }
    }

    var isLoading: Bool {
        switch state {
        case .loading: return true
        case .refreshing(let models): return models.isEmpty
        default: return false
        }
    }

    private var refreshAllLogs: String {
        if case .running(let logs, _, _) = refreshAllState { return logs }
        return ""
    }

    private func appendRefreshLog(_ text: String) {
        if case .running(let logs, let current, let total) = refreshAllState {
            refreshAllState = .running(logs: logs + text, current: current, total: total)
        }
    }

    private var analyzeAllLogs: String {
        if case .running(let logs, _, _) = analyzeAllState { return logs }
        return ""
    }

    enum RefreshError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message): return message
            }
        }
    }

    enum State {
        case uninitialized
        case loading
        case ready([PRModel])
        case refreshing([PRModel])
        case failed(String, prior: [PRModel]?)
    }

    enum RefreshAllState {
        case idle
        case running(logs: String, current: Int, total: Int)
        case completed(logs: String)

        var isRunning: Bool {
            switch self {
            case .idle, .completed: return false
            case .running: return true
            }
        }

        var progressText: String? {
            if case .running(_, let current, let total) = self {
                return total > 0 ? "\(current)/\(total)" : nil
            }
            return nil
        }
    }

    enum AnalyzeAllState {
        case idle
        case running(logs: String, current: Int, total: Int)
        case completed(logs: String)
        case failed(error: String, logs: String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }

        var progressText: String? {
            if case .running(_, let current, let total) = self {
                return "\(current)/\(total)"
            }
            return nil
        }
    }

}
