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
        case loading
        case running(stepName: String)
        case error(Error)
    }

    var state: State = .idle
    var currentOutput: String = ""
    var jobs: [PlanningJob] = []
    var selectedJob: PlanningJob?
    var selectedStepIndex: Int?
    var featureDescription: String = ""

    var selectedProviderName: String {
        didSet {
            if oldValue != selectedProviderName {
                rebuildUseCases()
            }
        }
    }

    var availableProviders: [(name: String, displayName: String)] {
        providerRegistry.providers.map { (name: $0.name, displayName: $0.displayName) }
    }

    private(set) var currentRepoName: String?
    private(set) var currentRepoPath: String?

    private var outputStore: AIOutputStore?
    private var store: ArchitecturePlannerStore?

    private let providerRegistry: ProviderRegistry
    private let dataPathsService: DataPathsService
    private let createJobUseCase: CreatePlanningJobUseCase
    private var compileArchInfoUseCase: CompileArchitectureInfoUseCase
    private var compileFollowupsUseCase: CompileFollowupsUseCase
    private var executeUseCase: ExecuteImplementationUseCase
    private var formRequirementsUseCase: FormRequirementsUseCase
    private let generateReportUseCase: GenerateReportUseCase
    private let manageGuidelinesUseCase: ManageGuidelinesUseCase
    private var planAcrossLayersUseCase: PlanAcrossLayersUseCase
    private var scoreConformanceUseCase: ScoreConformanceUseCase

    init(
        dataPathsService: DataPathsService,
        providerRegistry: ProviderRegistry,
        selectedProviderName: String? = nil
    ) {
        self.dataPathsService = dataPathsService
        self.providerRegistry = providerRegistry

        let client = selectedProviderName.flatMap { providerRegistry.client(named: $0) }
            ?? providerRegistry.providers.first!
        self.selectedProviderName = client.name

        self.compileArchInfoUseCase = CompileArchitectureInfoUseCase(client: client)
        self.compileFollowupsUseCase = CompileFollowupsUseCase(client: client)
        self.createJobUseCase = CreatePlanningJobUseCase()
        self.executeUseCase = ExecuteImplementationUseCase(client: client)
        self.formRequirementsUseCase = FormRequirementsUseCase(client: client)
        self.generateReportUseCase = GenerateReportUseCase()
        self.manageGuidelinesUseCase = ManageGuidelinesUseCase()
        self.planAcrossLayersUseCase = PlanAcrossLayersUseCase(client: client)
        self.scoreConformanceUseCase = ScoreConformanceUseCase(client: client)
    }

    private func rebuildUseCases() {
        guard let client = providerRegistry.client(named: selectedProviderName) else { return }
        compileArchInfoUseCase = CompileArchitectureInfoUseCase(client: client)
        compileFollowupsUseCase = CompileFollowupsUseCase(client: client)
        executeUseCase = ExecuteImplementationUseCase(client: client)
        formRequirementsUseCase = FormRequirementsUseCase(client: client)
        planAcrossLayersUseCase = PlanAcrossLayersUseCase(client: client)
        scoreConformanceUseCase = ScoreConformanceUseCase(client: client)
    }

    func loadJobs(repoName: String, repoPath: String) {
        currentRepoName = repoName
        currentRepoPath = repoPath

        do {
            let directoryURL = try dataPathsService.path(for: "architecture-planner", subdirectory: repoName)
            self.outputStore = AIOutputStore(baseDirectory: directoryURL.appendingPathComponent("output"))
            let store = try ArchitecturePlannerStore(directoryURL: directoryURL)
            self.store = store
            self.jobs = try manageGuidelinesUseCase.listJobs(repoName: repoName, store: store)
        } catch {
            state = .error(error)
        }
    }

    func createJob() async {
        guard let repoName = currentRepoName, let repoPath = currentRepoPath, let store else { return }
        guard !featureDescription.isEmpty else { return }

        state = .running(stepName: "Creating job...")
        do {
            let options = CreatePlanningJobUseCase.Options(
                repoName: repoName,
                repoPath: repoPath,
                featureDescription: featureDescription
            )
            let result = try createJobUseCase.run(options, store: store)
            featureDescription = ""
            jobs = try manageGuidelinesUseCase.listJobs(repoName: repoName, store: store)
            selectedJob = jobs.first { $0.jobId == result.jobId }
            state = .idle
        } catch {
            state = .error(error)
        }
    }

    func runNextStep() async {
        guard let job = selectedJob, let store, let repoPath = currentRepoPath else { return }

        let stepIndex = job.currentStepIndex
        guard let stepDef = ArchitecturePlannerStep(rawValue: stepIndex) else { return }

        state = .running(stepName: stepDef.name)
        currentOutput = ""

        let session = makeSession(jobId: job.jobId, stepIndex: stepIndex)

        do {
            switch stepDef {
            case .finalReport:
                _ = try generateReportUseCase.run(
                    GenerateReportUseCase.Options(jobId: job.jobId),
                    store: store
                )

            case .describeFeature, .reviewImplementationPlan:
                break

            default:
                try await session?.run(onOutput: { [weak self] text in
                    Task { @MainActor in
                        self?.currentOutput += text
                    }
                }) { outputHandler in
                    switch stepDef {
                    case .formRequirements:
                        let options = FormRequirementsUseCase.Options(jobId: job.jobId, repoPath: repoPath)
                        _ = try await self.formRequirementsUseCase.run(options, store: store, onOutput: outputHandler)

                    case .compileArchitectureInfo:
                        let options = CompileArchitectureInfoUseCase.Options(jobId: job.jobId, repoPath: repoPath)
                        _ = try await self.compileArchInfoUseCase.run(options, store: store, onOutput: outputHandler)

                    case .planAcrossLayers:
                        let options = PlanAcrossLayersUseCase.Options(jobId: job.jobId, repoPath: repoPath)
                        _ = try await self.planAcrossLayersUseCase.run(options, store: store, onOutput: outputHandler)

                    case .buildImplementationModel, .checklistValidation:
                        let options = ScoreConformanceUseCase.Options(jobId: job.jobId, repoPath: repoPath)
                        _ = try await self.scoreConformanceUseCase.run(options, store: store, onOutput: outputHandler)

                    case .executeImplementation:
                        let options = ExecuteImplementationUseCase.Options(jobId: job.jobId, repoPath: repoPath)
                        _ = try await self.executeUseCase.run(options, store: store, onOutput: outputHandler)

                    case .followups:
                        let options = CompileFollowupsUseCase.Options(jobId: job.jobId, repoPath: repoPath)
                        _ = try await self.compileFollowupsUseCase.run(options, store: store, onOutput: outputHandler)

                    default:
                        break
                    }
                }
            }

            reloadSelectedJob()
            state = .idle
        } catch {
            state = .error(error)
        }
    }

    func runAllSteps() async {
        while let job = selectedJob,
              ArchitecturePlannerStep(rawValue: job.currentStepIndex) != nil {
            await runNextStep()
            if case .error = state { break }
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

    private func makeSession(jobId: UUID, stepIndex: Int) -> AIRunSession? {
        guard let outputStore else { return nil }
        return AIRunSession(key: "\(jobId.uuidString)/\(stepIndex)", store: outputStore)
    }

    private func reloadSelectedJob() {
        guard let repoName = currentRepoName, let store else { return }
        do {
            jobs = try manageGuidelinesUseCase.listJobs(repoName: repoName, store: store)
            if let jobId = selectedJob?.jobId {
                selectedJob = jobs.first { $0.jobId == jobId }
            }
        } catch {
            state = .error(error)
        }
    }
}
