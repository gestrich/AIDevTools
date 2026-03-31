import AIOutputSDK
import ClaudeChainFeature
import ClaudeChainService
import DataPathsService
import Foundation
import GitHubService
import Logging
import PRRadarCLIService
import ProviderRegistryService

@MainActor @Observable
final class ClaudeChainModel {

    enum PhaseStatus {
        case completed
        case failed
        case pending
        case running
        case skipped
    }

    struct PhaseInfo: Identifiable {
        let displayName: String
        let id: String
        var status: PhaseStatus
    }

    struct ExecutionProgress {
        var currentPhase: String = ""
        var phases: [PhaseInfo] = []
        var taskDescription: String = ""
        var taskIndex: Int = 0
        var totalTasks: Int = 0
    }

    enum State {
        case completed(result: ExecuteChainUseCase.Result)
        case error(Error)
        case executing(progress: ExecutionProgress)
        case idle
        case loaded([ChainProject])
        case loadingChains
    }

    private let logger = Logger(label: "ClaudeChainModel")
    private(set) var chainDetailErrors: [String: Error] = [:]
    private(set) var chainDetailLoading: Set<String> = []
    private(set) var chainDetails: [String: ChainProjectDetail] = [:]
    private var chainDetailNetworkFetched: Set<String> = []
    private(set) var lastLoadedProjects: [ChainProject] = []
    private(set) var state: State = .idle
    var executionProgressObserver: (@MainActor (RunChainTaskUseCase.Progress) -> Void)?

    var selectedProviderName: String {
        didSet {
            if oldValue != selectedProviderName {
                rebuildClient()
            }
        }
    }

    var availableProviders: [(name: String, displayName: String)] {
        providerRegistry.providers.map { (name: $0.name, displayName: $0.displayName) }
    }

    private var activeClient: any AIClient
    private var changesTask: Task<Void, Never>?
    private var currentCredentialAccount: String?
    private var currentRepoPath: URL?
    private var gitHubPRService: (any GitHubPRServiceProtocol)?
    private let dataPathsService: DataPathsService
    private let listChainsUseCase: ListChainsUseCase
    private let providerRegistry: ProviderRegistry

    init(
        listChainsUseCase: ListChainsUseCase = ListChainsUseCase(),
        providerRegistry: ProviderRegistry,
        selectedProviderName: String? = nil,
        dataPathsService: DataPathsService
    ) {
        self.listChainsUseCase = listChainsUseCase
        self.providerRegistry = providerRegistry
        self.dataPathsService = dataPathsService

        guard let client = selectedProviderName.flatMap({ providerRegistry.client(named: $0) })
            ?? providerRegistry.defaultClient else {
            preconditionFailure("ClaudeChainModel requires at least one configured provider")
        }
        self.selectedProviderName = client.name
        self.activeClient = client
    }

    func loadChains(for repoPath: URL, credentialAccount: String?) {
        if currentRepoPath?.path != repoPath.path {
            chainDetailErrors = [:]
            chainDetailNetworkFetched = []
            chainDetails = [:]
            chainDetailLoading = []
            changesTask?.cancel()
            changesTask = nil
            gitHubPRService = nil
        }
        currentRepoPath = repoPath
        currentCredentialAccount = credentialAccount
        state = .loadingChains
        Task {
            do {
                let projects = try listChainsUseCase.run(options: .init(repoPath: repoPath))
                lastLoadedProjects = projects
                state = .loaded(projects)
            } catch {
                state = .error(error)
            }
        }
    }

    func loadChainDetail(projectName: String, repoPath: URL) {
        guard !chainDetailLoading.contains(projectName) else {
            logger.debug("loadChainDetail: already loading '\(projectName)', skipping")
            return
        }
        guard !chainDetailNetworkFetched.contains(projectName) else {
            logger.debug("loadChainDetail: already network-fetched '\(projectName)', skipping")
            return
        }
        chainDetailLoading.insert(projectName)
        logger.info("loadChainDetail: starting '\(projectName)'")
        Task {
            do {
                let service = try await makeOrGetGitHubPRService(repoPath: repoPath)
                let useCase = GetChainDetailUseCase(gitHubPRService: service)

                // Phase 1: show cached data immediately if available
                if chainDetails[projectName] == nil {
                    if let cached = try? await useCase.loadCached(options: .init(repoPath: repoPath, projectName: projectName)) {
                        let prCount = cached.enrichedTasks.filter { $0.enrichedPR != nil }.count
                        logger.info("loadChainDetail: cache hit for '\(projectName)' — \(prCount) PRs")
                        chainDetails[projectName] = cached
                    } else {
                        logger.info("loadChainDetail: no cache for '\(projectName)'")
                    }
                }

                // Phase 2: refresh from network
                logger.info("loadChainDetail: network fetch starting for '\(projectName)'")
                let detail = try await useCase.run(options: .init(repoPath: repoPath, projectName: projectName))
                let prCount = detail.enrichedTasks.filter { $0.enrichedPR != nil }.count
                logger.info("loadChainDetail: network fetch complete for '\(projectName)' — \(prCount) PRs, \(detail.actionItems.count) action items")
                chainDetails[projectName] = detail
                chainDetailNetworkFetched.insert(projectName)
            } catch {
                logger.error("loadChainDetail: failed for '\(projectName)': \(error)")
                chainDetailErrors[projectName] = error
            }
            chainDetailLoading.remove(projectName)
        }
    }

    func refreshChainDetail(projectName: String, repoPath: URL) {
        chainDetails.removeValue(forKey: projectName)
        chainDetailErrors.removeValue(forKey: projectName)
        chainDetailNetworkFetched.remove(projectName)
        loadChainDetail(projectName: projectName, repoPath: repoPath)
    }

    func executeChain(projectName: String, repoPath: URL) {
        state = .executing(progress: Self.initialProgress())
        Task {
            do {
                let useCase = ExecuteChainUseCase(client: activeClient)
                let result = try await useCase.run(
                    options: .init(repoPath: repoPath, projectName: projectName)
                ) { [weak self] progress in
                    guard let self else { return }
                    Task { @MainActor in
                        self.handleExecutionProgress(progress)
                    }
                }
                if result.success {
                    state = .completed(result: result)
                    loadChains(for: repoPath, credentialAccount: currentCredentialAccount)
                } else {
                    state = .error(
                        NSError(
                            domain: "ClaudeChainModel",
                            code: 0,
                            userInfo: [NSLocalizedDescriptionKey: result.message]
                        )
                    )
                }
            } catch {
                state = .error(error)
            }
        }
    }

    func makeChatModel(workingDirectory: String) -> ChatModel {
        let settings = ChatSettings()
        settings.resumeLastSession = false
        return ChatModel(configuration: ChatModelConfiguration(
            client: activeClient,
            settings: settings,
            workingDirectory: workingDirectory
        ))
    }

    func reset() {
        state = .idle
    }

    // MARK: - Private

    private func makeOrGetGitHubPRService(repoPath: URL) async throws -> any GitHubPRServiceProtocol {
        if let service = gitHubPRService { return service }
        let service = try await GitHubServiceFactory.createPRService(
            repoPath: repoPath.path,
            githubAccount: currentCredentialAccount ?? "",
            dataPathsService: dataPathsService
        )
        gitHubPRService = service
        startObservingChanges(service: service)
        return service
    }

    private func startObservingChanges(service: any GitHubPRServiceProtocol) {
        changesTask?.cancel()
        changesTask = Task { [weak self] in
            for await prNumber in service.changes() {
                guard let self else { break }
                guard let repoPath = currentRepoPath else { continue }
                let affectedProjects = chainDetails.filter { _, detail in
                    detail.enrichedTasks.contains { $0.enrichedPR?.pr.number == prNumber }
                }.keys
                for projectName in affectedProjects {
                    logger.info("startObservingChanges: PR #\(prNumber) changed, reloading '\(projectName)'")
                    chainDetails.removeValue(forKey: projectName)
                    chainDetailNetworkFetched.remove(projectName)
                    loadChainDetail(projectName: projectName, repoPath: repoPath)
                }
            }
        }
    }

    private func rebuildClient() {
        guard let client = providerRegistry.client(named: selectedProviderName) else { return }
        activeClient = client
    }

    private static func initialProgress() -> ExecutionProgress {
        ExecutionProgress(phases: [
            PhaseInfo(displayName: "Prepare", id: "prepare", status: .pending),
            PhaseInfo(displayName: "Pre-Script", id: "preScript", status: .pending),
            PhaseInfo(displayName: "AI Execution", id: "ai", status: .pending),
            PhaseInfo(displayName: "Post-Script", id: "postScript", status: .pending),
            PhaseInfo(displayName: "Finalize / Create PR", id: "finalize", status: .pending),
            PhaseInfo(displayName: "PR Summary", id: "summary", status: .pending),
            PhaseInfo(displayName: "Post PR Comment", id: "prComment", status: .pending),
        ])
    }

    private func handleExecutionProgress(_ progress: RunChainTaskUseCase.Progress) {
        guard case .executing(var current) = state else { return }

        switch progress {
        case .preparingProject:
            current.currentPhase = "Preparing project..."
            current.setPhaseStatus(id: "prepare", status: .running)
        case .preparedTask(let description, let index, let total):
            current.taskDescription = description
            current.taskIndex = index
            current.totalTasks = total
            current.setPhaseStatus(id: "prepare", status: .completed)
        case .runningPreScript:
            current.currentPhase = "Running pre-action script..."
            current.setPhaseStatus(id: "preScript", status: .running)
        case .preScriptCompleted(let result):
            current.setPhaseStatus(id: "preScript", status: result.success ? .completed : .skipped)
        case .runningAI(let taskDescription):
            current.currentPhase = "Running AI: \(taskDescription)"
            current.setPhaseStatus(id: "ai", status: .running)
        case .aiStreamEvent, .aiOutput:
            break
        case .aiCompleted:
            current.setPhaseStatus(id: "ai", status: .completed)
        case .runningPostScript:
            current.currentPhase = "Running post-action script..."
            current.setPhaseStatus(id: "postScript", status: .running)
        case .postScriptCompleted(let result):
            current.setPhaseStatus(id: "postScript", status: result.success ? .completed : .skipped)
        case .finalizing:
            current.currentPhase = "Finalizing..."
            current.setPhaseStatus(id: "finalize", status: .running)
        case .prCreated(let prNumber, _):
            current.currentPhase = "PR #\(prNumber) created"
            current.setPhaseStatus(id: "finalize", status: .completed)
        case .generatingSummary:
            current.currentPhase = "Generating PR summary..."
            current.setPhaseStatus(id: "summary", status: .running)
        case .summaryStreamEvent:
            break
        case .summaryCompleted:
            current.setPhaseStatus(id: "summary", status: .completed)
        case .postingPRComment:
            current.currentPhase = "Posting PR comment..."
            current.setPhaseStatus(id: "prComment", status: .running)
        case .prCommentPosted:
            current.setPhaseStatus(id: "prComment", status: .completed)
        case .completed:
            current.currentPhase = "Completed"
        case .failed(let phase, let error):
            current.currentPhase = "\(phase) failed: \(error)"
            // Mark the currently-running phase as failed
            if let idx = current.phases.firstIndex(where: { $0.status == .running }) {
                current.phases[idx].status = .failed
            }
        }

        state = .executing(progress: current)
        executionProgressObserver?(progress)
    }
}

extension ClaudeChainModel.ExecutionProgress {
    mutating func setPhaseStatus(id: String, status: ClaudeChainModel.PhaseStatus) {
        guard let idx = phases.firstIndex(where: { $0.id == id }) else { return }
        phases[idx].status = status
    }
}
