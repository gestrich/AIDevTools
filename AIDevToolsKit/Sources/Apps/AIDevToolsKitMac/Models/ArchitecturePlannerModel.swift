import AIOutputSDK
import ArchitecturePlannerFeature
import ArchitecturePlannerService
import DataPathsService
import Foundation
import ProviderRegistryService

@MainActor @Observable
final class ArchitecturePlannerModel {

    enum State {
        case idle
        case running(stepName: String, output: String)
        case error(Error)
    }

    private(set) var state: State = .idle
    private(set) var guidelines: [Guideline] = []
    private(set) var jobs: [PlanningJob] = []
    var selectedJob: PlanningJob?
    private(set) var selectedStepIndex: Int?
    var featureDescription: String = ""

    var selectedProviderName: String {
        didSet {
            if oldValue != selectedProviderName {
                rebuildRunStepUseCase()
            }
        }
    }

    var availableProviders: [(name: String, displayName: String)] {
        providerRegistry.providers.map { (name: $0.name, displayName: $0.displayName) }
    }

    var currentOutput: String {
        if case .running(_, let output) = state { return output }
        return ""
    }

    private(set) var currentRepoName: String?
    private(set) var currentRepoPath: String?

    private var outputStore: AIOutputStore?
    private var store: ArchitecturePlannerStore?

    private let createJobUseCase: CreatePlanningJobUseCase
    private let dataPathsService: DataPathsService
    private let generateReportUseCase: GenerateReportUseCase
    private let manageGuidelinesUseCase: ManageGuidelinesUseCase
    private let providerRegistry: ProviderRegistry
    private let seedGuidelinesUseCase: SeedGuidelinesUseCase
    private var useCases: UseCases

    init(
        dataPathsService: DataPathsService,
        providerRegistry: ProviderRegistry,
        selectedProviderName: String? = nil
    ) {
        self.dataPathsService = dataPathsService
        self.providerRegistry = providerRegistry

        guard let client = selectedProviderName.flatMap({ providerRegistry.client(named: $0) })
            ?? providerRegistry.defaultClient else {
            preconditionFailure("ProviderRegistry has no registered providers")
        }
        self.selectedProviderName = client.name

        self.createJobUseCase = CreatePlanningJobUseCase()
        self.generateReportUseCase = GenerateReportUseCase()
        self.manageGuidelinesUseCase = ManageGuidelinesUseCase()
        self.useCases = UseCases(client: client)
        self.seedGuidelinesUseCase = SeedGuidelinesUseCase()
    }

    private func rebuildRunStepUseCase() {
        guard let client = providerRegistry.client(named: selectedProviderName) else { return }
        useCases = UseCases(client: client)
    }

    func loadJobs(repoName: String, repoPath: String) {
        currentRepoName = repoName
        currentRepoPath = repoPath

        do {
            let workspace = try ArchitecturePlannerWorkspace(dataPathsService: dataPathsService, repoName: repoName)
            self.outputStore = workspace.outputStore
            self.store = workspace.plannerStore
            self.jobs = try manageGuidelinesUseCase.listJobs(repoName: repoName, store: workspace.plannerStore)
            self.guidelines = try manageGuidelinesUseCase.listGuidelines(repoName: repoName, store: workspace.plannerStore)
        } catch {
            state = .error(error)
        }
    }

    func createGuideline(_ options: ManageGuidelinesUseCase.CreateGuidelineOptions) {
        guard let store, let repoName = currentRepoName else { return }
        do {
            _ = try manageGuidelinesUseCase.createGuideline(options, store: store)
            guidelines = try manageGuidelinesUseCase.listGuidelines(repoName: repoName, store: store)
        } catch {
            state = .error(error)
        }
    }

    func deleteGuideline(_ guideline: Guideline) {
        guard let store, let repoName = currentRepoName else { return }
        do {
            try manageGuidelinesUseCase.deleteGuideline(guidelineId: guideline.guidelineId, store: store)
            guidelines = try manageGuidelinesUseCase.listGuidelines(repoName: repoName, store: store)
        } catch {
            state = .error(error)
        }
    }

    func seedGuidelines() {
        guard let repoName = currentRepoName, let repoPath = currentRepoPath, let store else { return }
        do {
            guidelines = try seedGuidelinesUseCase.runAndListGuidelines(
                SeedGuidelinesUseCase.Options(repoName: repoName, repoPath: repoPath),
                store: store
            )
        } catch {
            state = .error(error)
        }
    }

    func createJob() async {
        guard let repoName = currentRepoName, let repoPath = currentRepoPath, let store else { return }
        guard !featureDescription.isEmpty else { return }

        state = .running(stepName: "Creating job...", output: "")
        do {
            let options = CreatePlanningJobUseCase.Options(
                repoName: repoName,
                repoPath: repoPath,
                featureDescription: featureDescription
            )
            let result = try createJobUseCase.runAndListJobs(options, store: store)
            featureDescription = ""
            jobs = result.jobs
            selectedJob = result.jobs.first { $0.jobId == result.jobId }
            state = .idle
        } catch {
            state = .error(error)
        }
    }

    func runNextStep() async {
        guard let job = selectedJob, let store, let repoPath = currentRepoPath else { return }
        guard let stepDef = ArchitecturePlannerStep(rawValue: job.currentStepIndex) else { return }
        state = .running(stepName: stepDef.name, output: "")
        do {
            try await executeStep(stepDef, job: job, store: store, repoPath: repoPath)
            state = .idle
        } catch {
            state = .error(error)
        }
    }

    func runStep(_ step: ArchitecturePlannerStep) async {
        guard let job = selectedJob, let store, let repoPath = currentRepoPath else { return }
        state = .running(stepName: step.name, output: "")
        do {
            try await executeStep(step, job: job, store: store, repoPath: repoPath)
            state = .idle
        } catch {
            state = .error(error)
        }
    }

    func runAllSteps() async {
        guard let job = selectedJob, let store, let repoPath = currentRepoPath else { return }
        state = .running(stepName: "Running...", output: "")
        let options = RunAllPlanningStepsUseCase.Options(jobId: job.jobId, repoPath: repoPath)
        do {
            let updatedJob = try await useCases.runAllSteps.run(
                options,
                store: store,
                outputStore: outputStore,
                onStepStart: { [weak self] stepName in
                    Task { @MainActor in
                        guard let self else { return }
                        self.state = .running(stepName: stepName, output: "")
                    }
                },
                onOutput: { [weak self] text in
                    Task { @MainActor in self?.appendOutput(text) }
                }
            )
            if let updatedJob {
                selectedJob = updatedJob
                jobs = jobs.map { $0.jobId == updatedJob.jobId ? updatedJob : $0 }
            }
            state = .idle
        } catch {
            state = .error(error)
        }
    }

    func deleteJob(_ job: PlanningJob) {
        guard let store else { return }
        do {
            try manageGuidelinesUseCase.deleteJob(jobId: job.jobId, store: store)
            if selectedJob?.jobId == job.jobId {
                selectedJob = nil
            }
            if let repoName = currentRepoName {
                jobs = try manageGuidelinesUseCase.listJobs(repoName: repoName, store: store)
            }
        } catch {
            state = .error(error)
        }
    }

    func goToStep(_ index: Int) {
        selectedStepIndex = index
    }

    func generateReport() -> String? {
        guard let job = selectedJob, let store else { return nil }
        do {
            let result = try generateReportUseCase.run(
                GenerateReportUseCase.Options(jobId: job.jobId),
                store: store
            )
            return result.report
        } catch {
            state = .error(error)
            return nil
        }
    }

    func reset() {
        state = .idle
    }

    func loadOutput(jobId: UUID, stepIndex: Int) -> String? {
        makeSession(jobId: jobId, stepIndex: stepIndex)?.loadOutput()
    }

    // MARK: - Private

    private struct UseCases {
        let runAllSteps: RunAllPlanningStepsUseCase
        let runStep: RunPlanningStepUseCase

        init(client: any AIClient) {
            self.runAllSteps = RunAllPlanningStepsUseCase(client: client)
            self.runStep = RunPlanningStepUseCase(client: client)
        }
    }

    private func executeStep(
        _ step: ArchitecturePlannerStep,
        job: PlanningJob,
        store: ArchitecturePlannerStore,
        repoPath: String
    ) async throws {
        let session = makeSession(jobId: job.jobId, stepIndex: step.rawValue)
        let options = RunPlanningStepUseCase.Options(jobId: job.jobId, repoPath: repoPath, step: step)
        if let session {
            try await session.run(onOutput: { [weak self] text in
                Task { @MainActor in self?.appendOutput(text) }
            }) { outputHandler in
                try await self.useCases.runStep.run(options, store: store, onOutput: outputHandler)
            }
        } else {
            try await useCases.runStep.run(options, store: store)
        }
        if let updatedJob = try useCases.runStep.loadJob(jobId: job.jobId, store: store) {
            selectedJob = updatedJob
            jobs = jobs.map { $0.jobId == updatedJob.jobId ? updatedJob : $0 }
        }
    }

    private func appendOutput(_ text: String) {
        guard case .running(let stepName, let output) = state else { return }
        state = .running(stepName: stepName, output: output + text)
    }

    private func makeSession(jobId: UUID, stepIndex: Int) -> AIRunSession? {
        guard let outputStore else { return nil }
        return AIRunSession(key: "\(jobId.uuidString)/\(stepIndex)", store: outputStore)
    }

}
