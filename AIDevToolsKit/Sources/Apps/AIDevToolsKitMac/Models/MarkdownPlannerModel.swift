import AIOutputSDK
import ChatFeature
import Foundation
import Logging
import MarkdownPlannerFeature
import MarkdownPlannerService
import ProviderRegistryService
import RepositorySDK

struct QueuedTask: Identifiable {
    let id: UUID
    let description: String

    init(id: UUID = UUID(), description: String) {
        self.id = id
        self.description = description
    }
}

struct PlanPhase: Identifiable {
    var id: Int { index }
    let index: Int
    let description: String
    let isCompleted: Bool

    init(index: Int, description: String, isCompleted: Bool) {
        self.index = index
        self.description = description
        self.isCompleted = isCompleted
    }
}

@MainActor @Observable
final class MarkdownPlannerModel {

    enum State {
        case idle
        case executing(progress: ExecutionProgress)
        case generating(step: String)
        case completed(ExecutePlanUseCase.Result)
        case error(Error)
    }

    struct ExecutionProgress {
        var phases: [PhaseStatus] = []
        var currentPhaseIndex: Int?
        var currentPhaseDescription: String = ""
        var currentOutput: String = ""
        var phasesCompleted: Int = 0
        var totalPhases: Int = 0
    }

    var state: State = .idle
    var plans: [MarkdownPlanEntry] = []
    var isLoadingPlans: Bool = false
    var executionCompleteCount: Int = 0
    var phaseCompleteCount: Int = 0
    private(set) var currentRepository: RepositoryInfo?
    private(set) var lastExecutionPhases: [PhaseStatus] = []
    private(set) var queuedTasks: [QueuedTask] = []
    var executionProgressObserver: (@MainActor (ExecutePlanUseCase.Progress) -> Void)?

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
    private let dataPath: URL
    private let deletePlanUseCase: DeletePlanUseCase
    private let logger = Logger(label: "MarkdownPlannerModel")
    private let planSettingsStore: MarkdownPlannerRepoSettingsStore
    private let providerRegistry: ProviderRegistry
    private let togglePhaseUseCase: TogglePhaseUseCase

    init(
        dataPath: URL,
        deletePlanUseCase: DeletePlanUseCase = DeletePlanUseCase(),
        planSettingsStore: MarkdownPlannerRepoSettingsStore,
        providerRegistry: ProviderRegistry,
        selectedProviderName: String? = nil,
        togglePhaseUseCase: TogglePhaseUseCase = TogglePhaseUseCase()
    ) {
        self.dataPath = dataPath
        self.deletePlanUseCase = deletePlanUseCase
        self.planSettingsStore = planSettingsStore
        self.providerRegistry = providerRegistry
        self.togglePhaseUseCase = togglePhaseUseCase

        let client = selectedProviderName.flatMap { providerRegistry.client(named: $0) }
            ?? providerRegistry.defaultClient!
        self.selectedProviderName = client.name
        self.activeClient = client
    }

    private func rebuildClient() {
        guard let client = providerRegistry.client(named: selectedProviderName) else { return }
        activeClient = client
    }

    func loadPlans(for repo: RepositoryInfo) async {
        currentRepository = repo
        plans = []
        isLoadingPlans = true
        do {
            let proposedDir = try resolvedProposedDirectory(for: repo)
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

    /// Toggles a phase checkbox in the plan markdown and returns the updated content.
    func togglePhase(plan: MarkdownPlanEntry, phaseIndex: Int) throws -> String {
        let updatedContent = try togglePhaseUseCase.run(planURL: plan.planURL, phaseIndex: phaseIndex)
        Task { await reloadPlans() }
        return updatedContent
    }

    func completePlan(_ plan: MarkdownPlanEntry, repository: RepositoryInfo) throws {
        let settings = try planSettingsStore.settings(forRepoId: repository.id) ?? MarkdownPlannerRepoSettings(repoId: repository.id)
        let completedDir = settings.resolvedCompletedDirectory(repoPath: repository.path)
        try CompletePlanUseCase(completedDirectory: completedDir).run(planURL: plan.planURL)
        Task { await reloadPlans() }
    }

    func execute(
        plan: MarkdownPlanEntry,
        repository: RepositoryInfo,
        executeMode: ExecutePlanUseCase.ExecuteMode = .all,
        stopAfterArchitectureDiagram: Bool = false
    ) async {
        state = .executing(progress: ExecutionProgress())
        phaseCompleteCount = 0

        do {
            let settings = try planSettingsStore.settings(forRepoId: repository.id) ?? MarkdownPlannerRepoSettings(repoId: repository.id)
            let useCase = ExecutePlanUseCase(
                client: activeClient,
                completedDirectory: settings.resolvedCompletedDirectory(repoPath: repository.path),
                dataPath: dataPath
            )
            let options = ExecutePlanUseCase.Options(
                executeMode: executeMode,
                planPath: plan.planURL,
                repoPath: repository.path,
                repository: repository,
                stopAfterArchitectureDiagram: stopAfterArchitectureDiagram
            )
            let integrateUseCase = IntegrateTaskIntoPlanUseCase(client: activeClient)
            let result = try await useCase.run(options, onProgress: { [weak self] progress in
                guard let self else { return }
                Task { @MainActor in
                    self.handleExecutionProgress(progress)
                }
            }, betweenPhases: { [weak self] in
                guard let self else { return }
                let tasks = await MainActor.run { self.clearQueue() }
                guard !tasks.isEmpty else { return }
                let integrateOptions = IntegrateTaskIntoPlanUseCase.Options(
                    planPath: plan.planURL,
                    repoPath: repository.path,
                    taskDescriptions: tasks.map(\.description)
                )
                _ = try await integrateUseCase.run(integrateOptions)
            })
            if case .executing(let progress) = state {
                lastExecutionPhases = progress.phases
            }
            state = .completed(result)
            executionCompleteCount += 1
            await loadPlans(for: repository)
        } catch {
            state = .error(error)
        }
    }

    /// Generates a plan and returns the plan name (filename without extension) on success.
    @discardableResult
    func generate(prompt: String, repositories: [RepositoryInfo], selectedRepository: RepositoryInfo? = nil) async -> String? {
        state = .generating(step: selectedRepository != nil ? "Generating plan..." : "Matching repository...")

        let settingsStore = planSettingsStore
        let useCase = GeneratePlanUseCase(
            client: activeClient,
            resolveProposedDirectory: { repo in
                let settings = try settingsStore.settings(forRepoId: repo.id) ?? MarkdownPlannerRepoSettings(repoId: repo.id)
                return settings.resolvedProposedDirectory(repoPath: repo.path)
            }
        )
        let options = GeneratePlanUseCase.Options(
            prompt: prompt,
            repositories: repositories,
            selectedRepository: selectedRepository
        )

        do {
            let result = try await useCase.run(options) { [weak self] progress in
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
            logger.error("Plan generation failed: \(error.localizedDescription)")
            state = .error(error)
            return nil
        }
    }

    func makeChatModel(workingDirectory: String, systemPrompt: String? = nil) -> ChatModel {
        let settings = ChatSettings()
        settings.resumeLastSession = false
        return ChatModel(
            sendMessageUseCase: SendChatMessageUseCase(client: activeClient),
            client: activeClient,
            workingDirectory: workingDirectory,
            settings: settings,
            systemPrompt: systemPrompt
        )
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

    func reset() {
        state = .idle
    }

    // MARK: - Private

    private func handleExecutionProgress(_ progress: ExecutePlanUseCase.Progress) {
        guard case .executing(var current) = state else { return }

        switch progress {
        case .fetchingStatus:
            break
        case .phaseOverview(let phases):
            current.phases = phases
            current.totalPhases = phases.count
        case .startingPhase(let index, let total, let description):
            current.currentPhaseIndex = index
            current.totalPhases = total
            current.currentPhaseDescription = description
            current.currentOutput = ""
        case .phaseOutput(let text):
            current.currentOutput += text
        case .phaseCompleted(let index, _, _):
            current.phasesCompleted = index + 1
            current.currentOutput = ""
            if index < current.phases.count {
                current.phases[index] = PhaseStatus(
                    description: current.phases[index].description,
                    status: "completed"
                )
            }
            phaseCompleteCount += 1
        case .phaseFailed(_, let description, let error):
            current.currentPhaseDescription = "\(description) — Failed: \(error)"
        case .allCompleted(let phasesExecuted, _):
            current.phasesCompleted = phasesExecuted
        case .timeLimitReached:
            break
        case .uncommittedChanges:
            break
        }

        state = .executing(progress: current)
        executionProgressObserver?(progress)
    }

    static func parsePhases(from content: String) -> [PlanPhase] {
        var phases: [PlanPhase] = []
        var index = 0
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("## - [x] ") {
                let desc = String(line.dropFirst("## - [x] ".count))
                phases.append(PlanPhase(index: index, description: desc, isCompleted: true))
                index += 1
            } else if line.hasPrefix("## - [ ] ") {
                let desc = String(line.dropFirst("## - [ ] ".count))
                phases.append(PlanPhase(index: index, description: desc, isCompleted: false))
                index += 1
            }
        }
        return phases
    }

    private func resolvedProposedDirectory(for repo: RepositoryInfo) throws -> URL {
        let settings = try planSettingsStore.settings(forRepoId: repo.id) ?? MarkdownPlannerRepoSettings(repoId: repo.id)
        return settings.resolvedProposedDirectory(repoPath: repo.path)
    }
}
