import AIOutputSDK
import ClaudeChainFeature
import ClaudeChainService
import DataPathsService
import Foundation
import GitSDK
import Logging
import PipelineService
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
    private(set) var executionChatModel: ChatModel?

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
    private var currentGithubProfileId: String?
    private var currentRepoPath: URL?
    private let dataPathsService: DataPathsService
    private let gitClientFactory: @Sendable (String?) -> GitClient
    private let providerRegistry: ProviderRegistry
    private var useCases: UseCases

    private struct UseCases {
        let executeChain: ExecuteClaudeChainUseCase
        let loadChainDetail: LoadChainProjectDetailUseCase
        let loadChains: LoadClaudeChainsUseCase
        let prepareFinalizeStaged: PrepareFinalizeStagedChainUseCase

        init(
            client: any AIClient,
            dataPathsService: DataPathsService,
            gitClientFactory: @Sendable @escaping (String?) -> GitClient
        ) {
            executeChain = ExecuteClaudeChainUseCase(
                client: client,
                dataPathsService: dataPathsService,
                gitClientFactory: gitClientFactory
            )
            loadChainDetail = LoadChainProjectDetailUseCase(dataPathsService: dataPathsService)
            loadChains = LoadClaudeChainsUseCase(client: client, dataPathsService: dataPathsService)
            prepareFinalizeStaged = PrepareFinalizeStagedChainUseCase(client: client)
        }
    }

    init(
        providerRegistry: ProviderRegistry,
        selectedProviderName: String? = nil,
        dataPathsService: DataPathsService,
        gitClientFactory: @Sendable @escaping (String?) -> GitClient
    ) {
        self.providerRegistry = providerRegistry
        self.dataPathsService = dataPathsService
        self.gitClientFactory = gitClientFactory

        guard let client = selectedProviderName.flatMap({ providerRegistry.client(named: $0) })
            ?? providerRegistry.defaultClient else {
            preconditionFailure("ClaudeChainModel requires at least one configured provider")
        }
        self.selectedProviderName = client.name
        self.activeClient = client
        self.useCases = UseCases(
            client: client,
            dataPathsService: dataPathsService,
            gitClientFactory: gitClientFactory
        )
    }

    @discardableResult
    func loadChains(for repoPath: URL, githubCredentialProfileId: String?) -> Task<Void, Never> {
        if currentRepoPath?.path != repoPath.path {
            chainDetailErrors = [:]
            chainDetailNetworkFetched = []
            chatModels = [:]
            chainDetails = [:]
            chainDetailLoading = []
            fetchWarnings = []
        }
        currentRepoPath = repoPath
        currentGithubProfileId = githubCredentialProfileId
        state = .loadingChains
        return Task {
            do {
                let stream = await useCases.loadChains.stream(
                    repoPath: repoPath,
                    githubAccount: githubCredentialProfileId
                )
                for try await result in stream {
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
                let stream = try await useCases.loadChainDetail.stream(
                    project: project,
                    repoPath: repoPath,
                    githubAccount: currentGithubProfileId
                )
                for try await detail in stream {
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

    @discardableResult
    func executeChain(
        project: ChainProject,
        repoPath: URL,
        taskIndex: Int? = nil,
        stagingOnly: Bool = false,
        useWorktree: Bool = false
    ) -> Task<Void, Never> {
        state = .executing(progress: ExecutionProgress(phases: useCases.executeChain.phases(for: project)))
        executionChatModel = makeChatModel(workingDirectory: repoPath.path())
        streamAccumulator.reset()

        return Task {
            do {
                let result = try await useCases.executeChain.run(
                    options: .init(
                        githubAccount: currentGithubProfileId,
                        project: project,
                        repoPath: repoPath,
                        stagingOnly: stagingOnly,
                        taskIndex: taskIndex,
                        useWorktree: useWorktree
                    )
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
        state = .executing(progress: Self.finalizeProgress())
        selectedTaskIndex = index

        let pipelineModel = PipelineModel()
        taskPipelines[index] = pipelineModel

        pipelineModel.onEvent = { @MainActor [weak self] event in
            guard let self else { return }
            if case .nodeStarted(let id, _) = event, id == "pr-step" {
                self.handleExecutionProgress(.finalizing)
            }
        }

        Task {
            do {
                let prepared = try await useCases.prepareFinalizeStaged.run(
                    options: .init(
                        githubAccount: currentGithubProfileId,
                        project: project,
                        repoPath: repoPath,
                        taskIndex: index
                    )
                )
                let finalContext = try await pipelineModel.run(blueprint: prepared.blueprint)

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
                    taskDescription: prepared.task.description
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
        loadChains(for: repoPath, githubCredentialProfileId: currentGithubProfileId)
    }

    func reset() {
        state = .idle
        executionChatModel = nil
        taskPipelines = [:]
        selectedTaskIndex = nil
        if let repoPath = currentRepoPath {
            loadChains(for: repoPath, githubCredentialProfileId: currentGithubProfileId)
        }
    }

    func clearExecutionOutput() {
        executionChatModel = nil
    }

    // MARK: - Private

    private func rebuildClient() {
        guard let client = providerRegistry.client(named: selectedProviderName) else { return }
        activeClient = client
        useCases = UseCases(
            client: client,
            dataPathsService: dataPathsService,
            gitClientFactory: gitClientFactory
        )
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
            executionChatModel?.appendStatusMessage("Checking for open PRs...")
        case .creatingBranch(let b):
            current.setPhaseStatus(id: "prepare", status: .completed)
            executionChatModel?.appendStatusMessage("Creating branch: \(b)")
        case .creatingWorktree(let path):
            current.setPhaseStatus(id: "worktree", status: .running)
            executionChatModel?.appendStatusMessage("Creating worktree: \(URL(fileURLWithPath: path).lastPathComponent)")
        case .runningTasks:
            let worktreeStatus = current.phases.first(where: { $0.id == "worktree" })?.status
            if worktreeStatus == .running {
                current.setPhaseStatus(id: "worktree", status: .completed)
            } else {
                current.setPhaseStatus(id: "worktree", status: .skipped)
            }
            current.setPhaseStatus(id: "ai", status: .running)
            executionChatModel?.appendStatusMessage("Running sweep tasks...")
        case .taskStarted(let id):
            executionChatModel?.appendStatusMessage("Processing: \(id)")
            executionChatModel?.beginStreamingMessage()
        case .taskCompleted:
            executionChatModel?.finalizeCurrentStreamingMessage()
        case .contentBlocks(let blocks):
            executionChatModel?.updateCurrentStreamingBlocks(blocks)
            return
        case .creatingPR:
            current.setPhaseStatus(id: "ai", status: .completed)
            current.setPhaseStatus(id: "finalize", status: .running)
            executionChatModel?.appendStatusMessage("Creating PR...")
        case .prCreated(let url):
            current.setPhaseStatus(id: "finalize", status: .completed)
            executionChatModel?.appendStatusMessage("PR: \(url)")
        case .completed:
            current.setPhaseStatus(id: "ai", status: .completed)
            executionChatModel?.appendStatusMessage("Completed")
        }

        state = .executing(progress: current)
    }

    private func handleProgressEvent(_ event: ChainProgressEvent) {
        switch event {
        case .sweep(let progress): handleSweepProgress(progress)
        case .spec(let progress):
            if case .aiStreamEvent(let streamEvent) = progress {
                let blocks = streamAccumulator.apply(streamEvent)
                executionChatModel?.updateCurrentStreamingBlocks(blocks)
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
        updateExecutionChatModel(for: progress)
    }

    private func updateExecutionChatModel(for progress: RunSpecChainTaskUseCase.Progress) {
        guard let chatModel = executionChatModel else { return }
        switch progress {
        case .preparingProject:
            chatModel.appendStatusMessage("Preparing project...")
        case .preparedTask(let description, let index, let total):
            chatModel.appendStatusMessage("Task \(index + 1)/\(total): \(description)")
        case .runningPreScript:
            chatModel.appendStatusMessage("Running pre-action script...")
        case .preScriptCompleted(let result):
            chatModel.appendStatusMessage(result.success ? "Pre-script completed" : "Pre-script skipped")
        case .runningAI:
            chatModel.finalizeCurrentStreamingMessage()
            chatModel.appendStatusMessage("Starting AI execution...")
            chatModel.beginStreamingMessage()
        case .aiStreamEvent, .aiOutput:
            break
        case .aiCompleted:
            chatModel.finalizeCurrentStreamingMessage()
        case .runningPostScript:
            chatModel.appendStatusMessage("Running post-action script...")
        case .postScriptCompleted(let result):
            chatModel.appendStatusMessage(result.success ? "Post-script completed" : "Post-script skipped")
        case .finalizing:
            chatModel.appendStatusMessage("Finalizing...")
        case .prCreated(let prNumber, let prURL):
            chatModel.appendStatusMessage("PR created: #\(prNumber) \u{2014} \(prURL)")
        case .generatingSummary:
            chatModel.finalizeCurrentStreamingMessage()
            chatModel.appendStatusMessage("Generating PR summary...")
            chatModel.beginStreamingMessage()
        case .summaryStreamEvent:
            break
        case .summaryCompleted:
            chatModel.finalizeCurrentStreamingMessage()
        case .postingPRComment:
            chatModel.appendStatusMessage("Posting PR comment...")
        case .prCommentPosted:
            chatModel.appendStatusMessage("Summary posted to PR")
        case .completed(let prURL):
            chatModel.finalizeCurrentStreamingMessage()
            if let prURL {
                chatModel.appendStatusMessage("Completed \u{2014} PR: \(prURL)")
            } else {
                chatModel.appendStatusMessage("Completed")
            }
        case .runningReview:
            chatModel.appendStatusMessage("Running review...")
        case .reviewCompleted(let summary):
            chatModel.appendStatusMessage("Review: \(summary)")
        case .failed(let phase, let error):
            chatModel.finalizeCurrentStreamingMessage()
            chatModel.appendStatusMessage("Failed during \(phase): \(error)")
        }
    }
}

extension ClaudeChainModel.ExecutionProgress {
    mutating func setPhaseStatus(id: String, status: ChainPhaseStatus) {
        guard let idx = phases.firstIndex(where: { $0.id == id }) else { return }
        phases[idx].status = status
    }
}
