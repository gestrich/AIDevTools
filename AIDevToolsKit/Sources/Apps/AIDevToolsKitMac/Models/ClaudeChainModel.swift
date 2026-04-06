import AIOutputSDK
import ClaudeChainFeature
import ClaudeChainService
import CredentialService
import DataPathsService
import Foundation
import GitHubService
import GitSDK
import Logging
import PipelineService
import PRRadarCLIService
import ProviderRegistryService
import SweepFeature

@MainActor @Observable
final class ClaudeChainModel {

    struct ExecutionProgress {
        var currentPhase: String = ""
        var phases: [ChainExecutionPhase] = []
        var taskDescription: String = ""
        var taskIndex: Int = 0
        var totalTasks: Int = 0
    }

    enum State {
        case completed(result: ExecuteSpecChainUseCase.Result)
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
    private(set) var fetchWarnings: [ChainFetchFailure] = []
    private(set) var lastLoadedProjects: [ChainProject] = []
    private(set) var state: State = .idle
    private(set) var taskPipelines: [Int: PipelineModel] = [:]
    var selectedTaskIndex: Int?
    var executionContentBlocksObserver: (@MainActor ([AIContentBlock]) -> Void)?
    var executionProgressObserver: (@MainActor (RunSpecChainTaskUseCase.Progress) -> Void)?

    var selectedPipelineModel: PipelineModel? {
        taskPipelines[selectedTaskIndex ?? -1]
    }

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
    @ObservationIgnored private var chatModels: [String: ChatModel] = [:]
    @ObservationIgnored private let streamAccumulator = StreamAccumulator()
    private var currentCredentialAccount: String?
    private var currentRepoPath: URL?
    private var gitHubPRService: (any GitHubPRServiceProtocol)?
    private let dataPathsService: DataPathsService
    private let providerRegistry: ProviderRegistry

    init(
        providerRegistry: ProviderRegistry,
        selectedProviderName: String? = nil,
        dataPathsService: DataPathsService
    ) {
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
            chatModels = [:]
            chainDetails = [:]
            chainDetailLoading = []
            fetchWarnings = []
            gitHubPRService = nil
        }
        currentRepoPath = repoPath
        currentCredentialAccount = credentialAccount
        state = .loadingChains
        Task {
            let prService: any GitHubPRServiceProtocol
            do {
                prService = try await makeOrGetGitHubPRService(repoPath: repoPath)
            } catch {
                state = .error(error)
                return
            }
            let listChainsUseCase = ListChainsUseCase(client: activeClient, repoPath: repoPath, prService: prService)
            do {
                for try await result in listChainsUseCase.stream() {
                    lastLoadedProjects = result.projects
                    fetchWarnings = result.failures
                    state = .loaded(result.projects)
                    for project in result.projects {
                        loadChainDetail(project: project)
                    }
                }
            } catch {
                state = .error(error)
            }
        }
    }

    func loadChainDetail(project: ChainProject) {
        let projectName = project.name
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
                guard let repoPath = currentRepoPath else { return }
                let service = try await makeOrGetGitHubPRService(repoPath: repoPath)
                let useCase = GetChainDetailUseCase(gitHubPRService: service)
                for try await detail in useCase.stream(options: .init(project: project)) {
                    chainDetails[projectName] = detail
                }
                chainDetailNetworkFetched.insert(projectName)
            } catch {
                logger.error("loadChainDetail: failed for '\(projectName)': \(error)")
                chainDetailErrors[projectName] = error
            }
            chainDetailLoading.remove(projectName)
        }
    }

    func refreshChainDetail(project: ChainProject) {
        let projectName = project.name
        chainDetails.removeValue(forKey: projectName)
        chainDetailErrors.removeValue(forKey: projectName)
        chainDetailNetworkFetched.remove(projectName)
        loadChainDetail(project: project)
    }

    func executeChain(project: ChainProject, repoPath: URL, taskIndex: Int? = nil, stagingOnly: Bool = false) {
        let strategy = ChainExecutionStrategyFactory.strategy(for: project.kind)
        state = .executing(progress: ExecutionProgress(phases: strategy.initialPhases))
        streamAccumulator.reset()

        Task {
            let git = makeGitClient()
            do {
                let result = try await strategy.execute(
                    project: project,
                    repoPath: repoPath,
                    taskIndex: taskIndex,
                    stagingOnly: stagingOnly,
                    client: activeClient,
                    git: git,
                    githubAccount: currentCredentialAccount
                ) { [weak self] event in
                    Task { @MainActor [weak self] in
                        self?.handleProgressEvent(event)
                    }
                }
                state = .completed(result: result)
                refreshChainDetail(project: project)
            } catch {
                state = .error(error)
            }
        }
    }

    func finalizeStaged(at index: Int, project: ChainProject, repoPath: URL) {
        guard let task = project.tasks.first(where: { $0.index == index }) else { return }

        state = .executing(progress: Self.finalizeProgress())
        selectedTaskIndex = index

        let pipelineModel = PipelineModel()
        taskPipelines[index] = pipelineModel

        let taskHash = TaskService.generateTaskHash(description: task.description)
        let branchName = PRService.formatBranchName(projectName: project.name, taskHash: taskHash)

        let options = ChainRunOptions(
            baseBranch: project.baseBranch,
            branchName: branchName,
            githubAccount: currentCredentialAccount,
            projectName: project.name,
            repoPath: repoPath
        )

        pipelineModel.onEvent = { @MainActor [weak self] event in
            guard let self else { return }
            if case .nodeStarted(let id, _) = event, id == "pr-step" {
                self.handleExecutionProgress(.finalizing)
            }
        }

        Task {
            do {
                let blueprint = try await BuildFinalizePipelineUseCase(client: activeClient).run(task: task, options: options)
                let finalContext = try await pipelineModel.run(blueprint: blueprint)

                let prURL = finalContext[PRStep.prURLKey]
                let prNumber = finalContext[PRStep.prNumberKey]

                if let prNum = prNumber, let prURLStr = prURL {
                    handleExecutionProgress(.prCreated(prNumber: prNum, prURL: prURLStr))
                }
                handleExecutionProgress(.completed(prURL: prURL))

                let result = ExecuteSpecChainUseCase.Result(
                    success: true,
                    message: prURL.map { "PR created: \($0)" } ?? "Staged task finalized",
                    prURL: prURL,
                    prNumber: prNumber,
                    taskDescription: task.description
                )
                state = .completed(result: result)
                refreshChainDetail(project: project)
            } catch {
                state = .error(error)
            }
        }
    }

    func createPRFromStaged(project: ChainProject, repoPath: URL, result: ExecuteSpecChainUseCase.Result) {
        guard let taskDescription = result.taskDescription,
              let task = project.tasks.first(where: { $0.description == taskDescription }) else { return }
        finalizeStaged(at: task.index, project: project, repoPath: repoPath)
    }

    func persistentChatModel(for projectName: String, workingDirectory: String, systemPrompt: String) -> ChatModel {
        if let existing = chatModels[projectName] { return existing }
        let model = makeChatModel(workingDirectory: workingDirectory, systemPrompt: systemPrompt, includeMCP: true)
        chatModels[projectName] = model
        return model
    }

    func makeChatModel(workingDirectory: String, systemPrompt: String? = nil, includeMCP: Bool = false) -> ChatModel {
        let settings = ChatSettings()
        settings.resumeLastSession = false
        return ChatModel(configuration: ChatModelConfiguration(
            client: activeClient,
            mcpConfigPath: includeMCP ? DataPathsService.mcpConfigFileURL.path : nil,
            settings: settings,
            systemPrompt: systemPrompt,
            workingDirectory: workingDirectory
        ))
    }

    func createProject(name: String, baseBranch: String) throws {
        guard let repoPath = currentRepoPath else { return }
        try CreateChainProjectUseCase().run(
            options: .init(name: name, repoPath: repoPath, baseBranch: baseBranch)
        )
        loadChains(for: repoPath, credentialAccount: currentCredentialAccount)
    }

    func reset() {
        state = .idle
        taskPipelines = [:]
        selectedTaskIndex = nil
        if let repoPath = currentRepoPath {
            loadChains(for: repoPath, credentialAccount: currentCredentialAccount)
        }
    }

    // MARK: - Private

    private func makeGitClient() -> GitClient {
        guard let account = currentCredentialAccount else {
            return GitClient()
        }
        let resolver = CredentialResolver(
            settingsService: SecureSettingsService(),
            githubAccount: account
        )
        guard case .token(let token) = resolver.getGitHubAuth() else {
            return GitClient()
        }
        setenv("GH_TOKEN", token, 1)
        return GitClient(environment: ["GH_TOKEN": token])
    }

    private func makeOrGetGitHubPRService(repoPath: URL) async throws -> any GitHubPRServiceProtocol {
        if let service = gitHubPRService { return service }
        let service = try await GitHubServiceFactory.createPRService(
            repoPath: repoPath.path,
            githubAccount: currentCredentialAccount ?? "",
            dataPathsService: dataPathsService
        )
        gitHubPRService = service
        return service
    }

    private func rebuildClient() {
        guard let client = providerRegistry.client(named: selectedProviderName) else { return }
        activeClient = client
    }

    private static func finalizeProgress() -> ExecutionProgress {
        ExecutionProgress(phases: FinalizeStagedTaskUseCase.phases)
    }

    private func handleSweepProgress(_ progress: RunSweepBatchUseCase.Progress) {
        guard case .executing(var current) = state else { return }

        current.currentPhase = progress.displayText

        switch progress {
        case .checkingOpenPRs:
            current.setPhaseStatus(id: "prepare", status: .running)
        case .creatingBranch:
            current.setPhaseStatus(id: "prepare", status: .completed)
            current.setPhaseStatus(id: "ai", status: .running)
        case .creatingPR:
            current.setPhaseStatus(id: "ai", status: .completed)
            current.setPhaseStatus(id: "finalize", status: .running)
        case .prCreated:
            current.setPhaseStatus(id: "finalize", status: .completed)
        case .completed:
            current.setPhaseStatus(id: "ai", status: .completed)
        case .runningTasks, .taskStarted, .taskCompleted:
            break
        }

        state = .executing(progress: current)
    }

    private func handleProgressEvent(_ event: ChainProgressEvent) {
        switch event {
        case .sweep(let progress): handleSweepProgress(progress)
        case .spec(let progress):
            if case .aiStreamEvent(let streamEvent) = progress {
                let blocks = streamAccumulator.apply(streamEvent)
                executionContentBlocksObserver?(blocks)
            }
            handleExecutionProgress(progress)
        }
    }

    private func handleExecutionProgress(_ progress: RunSpecChainTaskUseCase.Progress) {
        guard case .executing(var current) = state else { return }

        let text = progress.displayText
        if !text.isEmpty {
            current.currentPhase = text
        }

        if let id = progress.phaseId, let status = progress.phaseStatus {
            current.setPhaseStatus(id: id, status: status)
        }

        if case .preparedTask(let description, let index, let total) = progress {
            current.taskDescription = description
            current.taskIndex = index
            current.totalTasks = total
        }

        if case .failed = progress {
            if let idx = current.phases.firstIndex(where: { $0.status == .running }) {
                current.phases[idx].status = .failed
            }
        }

        state = .executing(progress: current)
        executionProgressObserver?(progress)
    }
}

extension ClaudeChainModel.ExecutionProgress {
    mutating func setPhaseStatus(id: String, status: ChainPhaseStatus) {
        guard let idx = phases.firstIndex(where: { $0.id == id }) else { return }
        phases[idx].status = status
    }
}
