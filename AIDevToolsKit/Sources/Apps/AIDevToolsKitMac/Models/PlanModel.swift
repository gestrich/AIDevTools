import AIOutputSDK
import Foundation
import PlanFeature
import PlanService
import PipelineSDK
import ProviderRegistryService
import RepositorySDK

@MainActor @Observable
final class PlanModel {

    struct QueuedTask: Identifiable {
        let id: UUID
        let description: String

        init(id: UUID = UUID(), description: String) {
            self.id = id
            self.description = description
        }
    }

    enum State {
        case idle
        case executing
        case generating(step: String)
        case completed(PlanService.ExecuteResult, phases: [PlanPhase])
        case error(Error)

        var lastExecutionPhases: [PlanPhase] {
            switch self {
            case .completed(_, let phases): return phases
            default: return []
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var plans: [MarkdownPlanEntry] = []
    let pipelineModel = PipelineModel()
    private(set) var isLoadingPlans: Bool = false
    private(set) var executionCompleteCount: Int = 0
    private(set) var phaseCompleteCount: Int = 0
    private(set) var currentRepository: RepositoryConfiguration?
    private(set) var queuedTasks: [QueuedTask] = []

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
    private let deletePlanUseCase: DeletePlanUseCase
    private let mcpConfigPath: String?
    private let providerRegistry: ProviderRegistry
    private let togglePhaseUseCase: TogglePhaseUseCase

    init(
        deletePlanUseCase: DeletePlanUseCase = DeletePlanUseCase(),
        mcpConfigPath: String? = nil,
        providerRegistry: ProviderRegistry,
        selectedProviderName: String? = nil,
        togglePhaseUseCase: TogglePhaseUseCase = TogglePhaseUseCase()
    ) {
        self.deletePlanUseCase = deletePlanUseCase
        self.mcpConfigPath = mcpConfigPath
        self.providerRegistry = providerRegistry
        self.togglePhaseUseCase = togglePhaseUseCase

        guard let client = selectedProviderName.flatMap({ providerRegistry.client(named: $0) })
            ?? providerRegistry.defaultClient else {
            preconditionFailure("PlanModel requires at least one configured provider")
        }
        self.selectedProviderName = client.name
        self.activeClient = client
    }

    private func rebuildClient() {
        guard let client = providerRegistry.client(named: selectedProviderName) else { return }
        activeClient = client
    }

    func loadPlans(for repo: RepositoryConfiguration) async {
        if currentRepository?.id != repo.id {
            chatModels = [:]
        }
        currentRepository = repo
        plans = []
        isLoadingPlans = true
        do {
            let proposedDir = resolvedProposedDirectory(for: repo)
            let loaded = await LoadPlansUseCase(proposedDirectory: proposedDir).run()
            guard self.currentRepository?.id == repo.id else { return }
            self.plans = loaded
        } catch {
            state = .error(error)
        }
        self.isLoadingPlans = false
    }

    func deletePlan(_ plan: MarkdownPlanEntry) throws {
        try deletePlanUseCase.run(planURL: plan.planURL)
        plans.removeAll { $0.id == plan.id }
    }

    func reloadPlans() async {
        guard let repo = currentRepository else { return }
        await loadPlans(for: repo)
    }

    func getPlanDetails(planName: String, repository: RepositoryConfiguration) async throws -> String {
        let proposedDir = try resolvedProposedDirectory(for: repository)
        return try await GetPlanDetailsUseCase(proposedDirectory: proposedDir).run(planName: planName)
    }

    /// Toggles a phase checkbox in the plan markdown and returns the updated content.
    func togglePhase(plan: MarkdownPlanEntry, phaseIndex: Int) throws -> String {
        let updatedContent = try togglePhaseUseCase.run(planURL: plan.planURL, phaseIndex: phaseIndex)
        Task { await reloadPlans() }
        return updatedContent
    }

    func completePlan(_ plan: MarkdownPlanEntry, repository: RepositoryConfiguration) throws {
        let settings = repository.planner ?? PlanRepoSettings()
        let completedDir = settings.resolvedCompletedDirectory(repoPath: repository.path)
        try CompletePlanUseCase(completedDirectory: completedDir).run(planURL: plan.planURL)
        Task { await reloadPlans() }
    }

    func execute(
        plan: MarkdownPlanEntry,
        repository: RepositoryConfiguration,
        executeMode: PlanService.ExecuteMode = .all,
        stopAfterArchitectureDiagram: Bool = false
    ) async {
        state = .executing
        phaseCompleteCount = 0

        do {
            let service = PlanService(
                client: activeClient,
                resolveProposedDirectory: { repo in
                    let s = repo.planner ?? PlanRepoSettings()
                    return s.resolvedProposedDirectory(repoPath: repo.path)
                }
            )
            let options = PlanService.ExecuteOptions(
                executeMode: executeMode,
                planPath: plan.planURL,
                repoPath: repository.path,
                repository: repository,
                stopAfterArchitectureDiagram: stopAfterArchitectureDiagram
            )
            let blueprint = try await service.buildExecutePipeline(
                options: options,
                pendingTasksProvider: { [weak self] in
                    guard let self else { return [] }
                    return await MainActor.run { self.clearQueue().map(\.description) }
                }
            )
            try await pipelineModel.run(blueprint: blueprint)
            let completedCount = pipelineModel.nodes.filter(\.isCompleted).count
            let totalCount = pipelineModel.nodes.count
            let result = PlanService.ExecuteResult(
                phasesExecuted: completedCount,
                totalPhases: totalCount,
                allCompleted: totalCount > 0 && completedCount == totalCount,
                totalSeconds: 0
            )
            state = .completed(result, phases: [])
            executionCompleteCount += 1
            await loadPlans(for: repository)
        } catch {
            state = .error(error)
        }
    }

    /// Generates a plan and returns the plan name (filename without extension) on success.
    @discardableResult
    func generate(prompt: String, repositories: [RepositoryConfiguration], selectedRepository: RepositoryConfiguration? = nil) async -> String? {
        state = .generating(step: selectedRepository != nil ? "Generating plan..." : "Matching repository...")

        let service = PlanService(
            client: activeClient,
            resolveProposedDirectory: { repo in
                let settings = repo.planner ?? PlanRepoSettings()
                return settings.resolvedProposedDirectory(repoPath: repo.path)
            }
        )
        let options = PlanService.GenerateOptions(
            prompt: prompt,
            repositories: repositories,
            selectedRepository: selectedRepository
        )

        do {
            let result = try await service.generate(options: options) { [weak self] progress in
                guard let self else { return }
                Task { @MainActor in
                    switch progress {
                    case .matchingRepo:
                        self.state = .generating(step: "Matching repository...")
                    case .matchedRepo(_, let request):
                        self.state = .generating(step: "Matched: \(request)")
                    case .generatingPlan:
                        self.state = .generating(step: "Generating plan...")
                    case .generatedPlan(let filename):
                        self.state = .generating(step: "Generated: \(filename)")
                    case .writingPlan:
                        self.state = .generating(step: "Writing plan...")
                    case .completed:
                        break
                    }
                }
            }
            await loadPlans(for: result.repository)
            let planName = result.planURL.deletingPathExtension().lastPathComponent
            state = .idle
            return planName
        } catch {
            state = .error(error)
            return nil
        }
    }

    func persistentChatModel(for planName: String, workingDirectory: String, systemPrompt: String) -> ChatModel {
        if let existing = chatModels[planName] { return existing }
        let model = makeChatModel(workingDirectory: workingDirectory, systemPrompt: systemPrompt)
        chatModels[planName] = model
        return model
    }

    func makeChatModel(workingDirectory: String, systemPrompt: String? = nil) -> ChatModel {
        let settings = ChatSettings()
        settings.resumeLastSession = false
        return ChatModel(configuration: ChatModelConfiguration(
            client: activeClient,
            mcpConfigPath: mcpConfigPath,
            settings: settings,
            systemPrompt: systemPrompt,
            workingDirectory: workingDirectory
        ))
    }

    func queueTask(_ description: String) {
        queuedTasks.append(QueuedTask(description: description))
    }

    func removeQueuedTask(_ id: UUID) {
        queuedTasks.removeAll { $0.id == id }
    }

    func clearQueue() -> [QueuedTask] {
        let tasks = queuedTasks
        queuedTasks = []
        return tasks
    }

    func appendReviewTemplate(_ template: ReviewTemplate, to planURL: URL) async throws {
        try await AppendReviewTemplateUseCase().run(.init(planURL: planURL, template: template))
    }

    func reportError(_ error: Error) {
        state = .error(error)
    }

    func reset() {
        state = .idle
    }

    // MARK: - Private

    private func resolvedProposedDirectory(for repo: RepositoryConfiguration) -> URL {
        let settings = repo.planner ?? PlanRepoSettings()
        return settings.resolvedProposedDirectory(repoPath: repo.path)
    }
}
