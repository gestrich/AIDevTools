import AIOutputSDK
import Foundation
import GitHubService
import Logging
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import PRReviewFeature
import ProviderRegistryService

private let logger = Logger(label: "AllPRsModel")

@Observable
@MainActor
final class AllPRsModel {

    private(set) var state: State = .uninitialized
    private(set) var refreshAllState: RefreshAllState = .idle
    private(set) var analyzeAllState: AnalyzeAllState = .idle
    private(set) var fetchingPRNumbers: Set<Int> = []
    private(set) var loadedAuthors: [AuthorCacheEntry] = []
    var showOnlyWithPendingComments: Bool = false
    var selectedProviderName: String = ""

    let config: PRRadarRepoConfig
    private let providerRegistry: ProviderRegistry

    var aiClient: (any AIClient)? {
        providerRegistry.client(named: selectedProviderName) ?? providerRegistry.defaultClient
    }

    init(config: PRRadarRepoConfig, providerRegistry: ProviderRegistry) {
        self.config = config
        self.providerRegistry = providerRegistry
    }

    // MARK: - Cache Load

    func loadCached() async {
        state = .loading
        if let gitHubConfig = try? config.makeGitHubRepoConfig() {
            // Swallowing intentionally: author metadata is cosmetic; a failure leaves
            // login names displayed instead of full names, which is acceptable degradation.
            loadedAuthors = (try? await LoadAuthorsUseCase(config: gitHubConfig).executeAll()) ?? []
        }
        let models = applyMetadata(await cachedPRs(filter: config.makeFilter()))
        logger.info("loadCached: loaded \(models.count) models", metadata: ["repo": "\(config.name)"])
        loadSummariesInBackground(for: models)
    }

    // MARK: - GitHub Refresh

    func refresh(number: Int) async throws -> PRModel? {
        fetchingPRNumbers.insert(number)
        defer { fetchingPRNumbers.remove(number) }

        let useCase = GitHubPRLoaderUseCase(config: try config.makeGitHubRepoConfig())
        var fetchError: String?

        for await event in useCase.execute(prNumber: number) {
            switch event {
            case .prFetchStarted:
                break
            case .prUpdated(let metadata):
                if let model = currentPRModels?.first(where: { $0.prNumber == metadata.number }) {
                    model.updateMetadata(metadata)
                    await model.loadSummary()
                }
            case .prFetchFailed(_, let error):
                fetchError = error
            case .completed:
                break
            default:
                break
            }
        }

        if let error = fetchError {
            throw RefreshError.failed(error)
        }

        return currentPRModels?.first(where: { $0.metadata.number == number })
    }

    func refresh(filter: PRFilter) async {
        let prior = currentPRModels
        self.state = .refreshing(prior ?? [])
        refreshAllState = .running(logs: "Fetching PR list from GitHub...\n", current: 0, total: 0)

        let gitHubConfig: GitHubRepoConfig
        do {
            gitHubConfig = try config.makeGitHubRepoConfig()
        } catch {
            self.state = .failed(error.localizedDescription, prior: prior)
            refreshAllState = .completed(logs: "Failed: \(error.localizedDescription)\n")
            return
        }
        loadedAuthors = (try? await LoadAuthorsUseCase(config: gitHubConfig).executeAll()) ?? loadedAuthors

        let useCase = GitHubPRLoaderUseCase(config: gitHubConfig)
        var fetchedTotal = 0
        var enrichedCount = 0

        for await event in useCase.execute(filter: filter) {
            switch event {
            case .listLoadStarted:
                break

            case .cached(let metadata):
                let models = applyMetadata(metadata)
                loadSummariesInBackground(for: models)

            case .listFetchStarted:
                break

            case .fetched(let metadata):
                fetchedTotal = metadata.count
                appendRefreshLog("Found \(fetchedTotal) PRs\n")
                refreshAllState = .running(logs: refreshAllLogs, current: 0, total: fetchedTotal)
                let models = applyMetadata(metadata)
                loadSummariesInBackground(for: models)

            case .listFetchFailed(let message):
                logger.error("refresh() list fetch failed", metadata: ["error": "\(message)", "repo": "\(config.name)"])
                self.state = .failed(message, prior: prior)
                refreshAllState = .completed(logs: refreshAllLogs + "Failed: \(message)\n")
                return

            case .prFetchStarted(let prNumber):
                fetchingPRNumbers.insert(prNumber)
                appendRefreshLog("PR #\(prNumber): fetching...\n")

            case .prUpdated(let metadata):
                fetchingPRNumbers.remove(metadata.number)
                enrichedCount += 1
                appendRefreshLog("[\(enrichedCount)/\(fetchedTotal)] PR #\(metadata.number): \(metadata.title)\n")
                refreshAllState = .running(logs: refreshAllLogs, current: enrichedCount, total: fetchedTotal)
                if let model = currentPRModels?.first(where: { $0.prNumber == metadata.number }) {
                    model.updateMetadata(metadata)
                    Task { await model.loadSummary() }
                }

            case .prFetchFailed(let prNumber, let error):
                fetchingPRNumbers.remove(prNumber)
                enrichedCount += 1
                logger.error("refresh() PR enrichment failed", metadata: ["pr": "\(prNumber)", "error": "\(error)", "repo": "\(config.name)"])
                refreshAllState = .running(logs: refreshAllLogs, current: enrichedCount, total: fetchedTotal)

            case .completed:
                refreshAllState = .completed(logs: refreshAllLogs + "\nRefresh complete.\n")
                // Swallowing intentionally: author metadata is cosmetic; retaining stale
                // data on failure is acceptable degradation.
                loadedAuthors = (try? await LoadAuthorsUseCase(config: gitHubConfig).executeAll()) ?? loadedAuthors
            }
        }
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

            if await pr.runAnalysis(aiClient: aiClient, ruleFilePaths: ruleFilePaths) {
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
        logger.info("applyMetadata: state=ready(\(models.count))", metadata: ["repo": "\(config.name)"])
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
        loadedAuthors
            .map { AuthorOption(login: $0.login, name: $0.name, avatarURL: $0.avatarURL) }
            .sorted { $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending }
    }

    func authorDisplayName(for author: PRMetadata.Author) -> String {
        if !author.name.isEmpty { return author.name }
        return loadedAuthors.first(where: { $0.login == author.login })?.name ?? author.login
    }

    func filteredPRs(_ models: [PRModel], filter: PRFilter = PRFilter()) -> [PRModel] {
        var result = models.filter { filter.matches($0.metadata) }
        if showOnlyWithPendingComments {
            result = result.filter { $0.hasPendingComments }
        }
        return result
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
