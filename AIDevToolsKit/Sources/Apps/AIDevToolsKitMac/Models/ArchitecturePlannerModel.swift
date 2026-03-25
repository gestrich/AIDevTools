import ArchitecturePlannerFeature
import ArchitecturePlannerService
import DataPathsService
import Foundation

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

    private(set) var currentRepoName: String?
    private(set) var currentRepoPath: String?

    private var store: ArchitecturePlannerStore?

    private let dataPathsService: DataPathsService
    private let createJobUseCase: CreatePlanningJobUseCase
    private let compileArchInfoUseCase: CompileArchitectureInfoUseCase
    private let compileFollowupsUseCase: CompileFollowupsUseCase
    private let executeUseCase: ExecuteImplementationUseCase
    private let formRequirementsUseCase: FormRequirementsUseCase
    private let generateReportUseCase: GenerateReportUseCase
    private let manageGuidelinesUseCase: ManageGuidelinesUseCase
    private let planAcrossLayersUseCase: PlanAcrossLayersUseCase
    private let scoreConformanceUseCase: ScoreConformanceUseCase

    init(
        dataPathsService: DataPathsService,
        compileArchInfoUseCase: CompileArchitectureInfoUseCase = CompileArchitectureInfoUseCase(),
        compileFollowupsUseCase: CompileFollowupsUseCase = CompileFollowupsUseCase(),
        createJobUseCase: CreatePlanningJobUseCase = CreatePlanningJobUseCase(),
        executeUseCase: ExecuteImplementationUseCase = ExecuteImplementationUseCase(),
        formRequirementsUseCase: FormRequirementsUseCase = FormRequirementsUseCase(),
        generateReportUseCase: GenerateReportUseCase = GenerateReportUseCase(),
        manageGuidelinesUseCase: ManageGuidelinesUseCase = ManageGuidelinesUseCase(),
        planAcrossLayersUseCase: PlanAcrossLayersUseCase = PlanAcrossLayersUseCase(),
        scoreConformanceUseCase: ScoreConformanceUseCase = ScoreConformanceUseCase()
    ) {
        self.dataPathsService = dataPathsService
        self.compileArchInfoUseCase = compileArchInfoUseCase
        self.compileFollowupsUseCase = compileFollowupsUseCase
        self.createJobUseCase = createJobUseCase
        self.executeUseCase = executeUseCase
        self.formRequirementsUseCase = formRequirementsUseCase
        self.generateReportUseCase = generateReportUseCase
        self.manageGuidelinesUseCase = manageGuidelinesUseCase
        self.planAcrossLayersUseCase = planAcrossLayersUseCase
        self.scoreConformanceUseCase = scoreConformanceUseCase
    }

    func loadJobs(repoName: String, repoPath: String) {
        currentRepoName = repoName
        currentRepoPath = repoPath

        do {
            let directoryURL = try dataPathsService.path(for: "architecture-planner", subdirectory: repoName)
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

        let outputHandler: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor in
                self?.currentOutput += text
            }
        }

        do {
            switch stepDef {
            case .formRequirements:
                let options = FormRequirementsUseCase.Options(jobId: job.jobId, repoPath: repoPath)
                _ = try await formRequirementsUseCase.run(options, store: store, onOutput: outputHandler)

            case .compileArchitectureInfo:
                let options = CompileArchitectureInfoUseCase.Options(jobId: job.jobId, repoPath: repoPath)
                _ = try await compileArchInfoUseCase.run(options, store: store, onOutput: outputHandler)

            case .planAcrossLayers:
                let options = PlanAcrossLayersUseCase.Options(jobId: job.jobId, repoPath: repoPath)
                _ = try await planAcrossLayersUseCase.run(options, store: store, onOutput: outputHandler)

            case .buildImplementationModel, .checklistValidation:
                let options = ScoreConformanceUseCase.Options(jobId: job.jobId, repoPath: repoPath)
                _ = try await scoreConformanceUseCase.run(options, store: store, onOutput: outputHandler)

            case .executeImplementation:
                let options = ExecuteImplementationUseCase.Options(jobId: job.jobId, repoPath: repoPath)
                _ = try await executeUseCase.run(options, store: store, onOutput: outputHandler)

            case .finalReport:
                _ = try generateReportUseCase.run(
                    GenerateReportUseCase.Options(jobId: job.jobId),
                    store: store
                )

            case .followups:
                let options = CompileFollowupsUseCase.Options(jobId: job.jobId, repoPath: repoPath)
                _ = try await compileFollowupsUseCase.run(options, store: store, onOutput: outputHandler)

            case .describeFeature, .reviewImplementationPlan:
                break // These are interactive steps handled via UI
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

    // MARK: - Private

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
