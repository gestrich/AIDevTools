import Foundation
import PlanRunnerFeature
import PlanRunnerService
import RepositorySDK

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
final class PlanRunnerModel {

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
    var plans: [PlanEntry] = []
    var isLoadingPlans: Bool = false
    var executionCompleteCount: Int = 0
    private(set) var currentRepository: RepositoryInfo?

    private let completePlanUseCase: CompletePlanUseCase
    private let dataPath: URL
    private let deletePlanUseCase: DeletePlanUseCase
    private let executePlan: ExecutePlanUseCase
    private let generatePlan: GeneratePlanUseCase
    private let loadPlansUseCase: LoadPlansUseCase
    private let planSettingsStore: PlanRepoSettingsStore
    private let togglePhaseUseCase: TogglePhaseUseCase

    init(
        completePlanUseCase: CompletePlanUseCase = CompletePlanUseCase(),
        dataPath: URL,
        deletePlanUseCase: DeletePlanUseCase = DeletePlanUseCase(),
        executePlan: ExecutePlanUseCase = ExecutePlanUseCase(),
        generatePlan: GeneratePlanUseCase = GeneratePlanUseCase(),
        loadPlansUseCase: LoadPlansUseCase = LoadPlansUseCase(),
        planSettingsStore: PlanRepoSettingsStore,
        togglePhaseUseCase: TogglePhaseUseCase = TogglePhaseUseCase()
    ) {
        self.completePlanUseCase = completePlanUseCase
        self.dataPath = dataPath
        self.deletePlanUseCase = deletePlanUseCase
        self.executePlan = executePlan
        self.generatePlan = generatePlan
        self.loadPlansUseCase = loadPlansUseCase
        self.planSettingsStore = planSettingsStore
        self.togglePhaseUseCase = togglePhaseUseCase
    }

    func loadPlans(for repo: RepositoryInfo) async {
        currentRepository = repo
        plans = []
        isLoadingPlans = true
        let proposedDir = resolvedProposedDirectory(for: repo)
        let loaded = await loadPlansUseCase.run(proposedDirectory: proposedDir)
        guard self.currentRepository?.id == repo.id else { return }
        self.plans = loaded
        self.isLoadingPlans = false
    }

    func deletePlan(_ plan: PlanEntry) throws {
        try deletePlanUseCase.run(planURL: plan.planURL)
        plans.removeAll { $0.id == plan.id }
    }

    func reloadPlans() async {
        guard let repo = currentRepository else { return }
        await loadPlans(for: repo)
    }

    /// Toggles a phase checkbox in the plan markdown and returns the updated content.
    func togglePhase(plan: PlanEntry, phaseIndex: Int) throws -> String {
        let updatedContent = try togglePhaseUseCase.run(planURL: plan.planURL, phaseIndex: phaseIndex)
        Task { await reloadPlans() }
        return updatedContent
    }

    /// Moves a plan from proposed to completed directory and refreshes the plan list.
    func completePlan(_ plan: PlanEntry, repository: RepositoryInfo) throws {
        let settings = (try? planSettingsStore.settings(forRepoId: repository.id)) ?? PlanRepoSettings(repoId: repository.id)
        let completedDir = settings.resolvedCompletedDirectory(repoPath: repository.path)
        try completePlanUseCase.run(planURL: plan.planURL, completedDirectory: completedDir)
        Task { await reloadPlans() }
    }

    func execute(plan: PlanEntry, repository: RepositoryInfo) async {
        state = .executing(progress: ExecutionProgress())

        let settings = (try? planSettingsStore.settings(forRepoId: repository.id)) ?? PlanRepoSettings(repoId: repository.id)
        let options = ExecutePlanUseCase.Options(
            planPath: plan.planURL,
            repoPath: repository.path,
            repository: repository,
            completedDirectory: settings.resolvedCompletedDirectory(repoPath: repository.path),
            dataPath: dataPath
        )

        do {
            let result = try await executePlan.run(options) { [weak self] progress in
                guard let self else { return }
                Task { @MainActor in
                    self.handleExecutionProgress(progress)
                }
            }
            state = .completed(result)
            executionCompleteCount += 1
            await loadPlans(for: repository)
        } catch {
            state = .error(error)
        }
    }

    func generate(voiceText: String, repositories: [RepositoryInfo]) async {
        state = .generating(step: "Matching repository...")

        let settingsStore = planSettingsStore
        let options = GeneratePlanUseCase.Options(
            voiceText: voiceText,
            repositories: repositories,
            resolveProposedDirectory: { repo in
                let settings = (try? settingsStore.settings(forRepoId: repo.id)) ?? PlanRepoSettings(repoId: repo.id)
                return settings.resolvedProposedDirectory(repoPath: repo.path)
            }
        )

        do {
            let result = try await generatePlan.run(options) { [weak self] progress in
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
            state = .idle
        } catch {
            state = .error(error)
        }
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
        case .phaseFailed(_, let description, let error):
            current.currentPhaseDescription = "\(description) — Failed: \(error)"
        case .allCompleted(let phasesExecuted, _):
            current.phasesCompleted = phasesExecuted
        case .timeLimitReached:
            break
        }

        state = .executing(progress: current)
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

    private func resolvedProposedDirectory(for repo: RepositoryInfo) -> URL {
        let settings = (try? planSettingsStore.settings(forRepoId: repo.id)) ?? PlanRepoSettings(repoId: repo.id)
        return settings.resolvedProposedDirectory(repoPath: repo.path)
    }
}
