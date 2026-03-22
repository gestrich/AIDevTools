import ArchitecturePlannerFeature
import ArchitecturePlannerService
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
    var jobs: [PlanningJob] = []
    var selectedJob: PlanningJob?
    var selectedStepIndex: Int?
    var featureDescription: String = ""

    private(set) var currentRepoName: String?
    private(set) var currentRepoPath: String?

    private var store: ArchitecturePlannerStore?

    private let createJobUseCase: CreatePlanningJobUseCase
    private let compileArchInfoUseCase: CompileArchitectureInfoUseCase
    private let executeUseCase: ExecuteImplementationUseCase
    private let formRequirementsUseCase: FormRequirementsUseCase
    private let generateReportUseCase: GenerateReportUseCase
    private let manageGuidelinesUseCase: ManageGuidelinesUseCase
    private let planAcrossLayersUseCase: PlanAcrossLayersUseCase
    private let scoreConformanceUseCase: ScoreConformanceUseCase

    init(
        compileArchInfoUseCase: CompileArchitectureInfoUseCase = CompileArchitectureInfoUseCase(),
        createJobUseCase: CreatePlanningJobUseCase = CreatePlanningJobUseCase(),
        executeUseCase: ExecuteImplementationUseCase = ExecuteImplementationUseCase(),
        formRequirementsUseCase: FormRequirementsUseCase = FormRequirementsUseCase(),
        generateReportUseCase: GenerateReportUseCase = GenerateReportUseCase(),
        manageGuidelinesUseCase: ManageGuidelinesUseCase = ManageGuidelinesUseCase(),
        planAcrossLayersUseCase: PlanAcrossLayersUseCase = PlanAcrossLayersUseCase(),
        scoreConformanceUseCase: ScoreConformanceUseCase = ScoreConformanceUseCase()
    ) {
        self.compileArchInfoUseCase = compileArchInfoUseCase
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
            let store = try ArchitecturePlannerStore(repoName: repoName)
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

        do {
            switch stepDef {
            case .formRequirements:
                let options = FormRequirementsUseCase.Options(jobId: job.jobId, repoPath: repoPath)
                _ = try await formRequirementsUseCase.run(options, store: store)

            case .compileArchitectureInfo:
                let options = CompileArchitectureInfoUseCase.Options(jobId: job.jobId, repoPath: repoPath)
                _ = try await compileArchInfoUseCase.run(options, store: store)

            case .planAcrossLayers:
                let options = PlanAcrossLayersUseCase.Options(jobId: job.jobId, repoPath: repoPath)
                _ = try await planAcrossLayersUseCase.run(options, store: store)

            case .buildImplementationModel, .checklistValidation:
                let options = ScoreConformanceUseCase.Options(jobId: job.jobId, repoPath: repoPath)
                _ = try await scoreConformanceUseCase.run(options, store: store)

            case .executeImplementation:
                let options = ExecuteImplementationUseCase.Options(jobId: job.jobId, repoPath: repoPath)
                _ = try await executeUseCase.run(options, store: store)

            case .finalReport:
                _ = try generateReportUseCase.run(
                    GenerateReportUseCase.Options(jobId: job.jobId),
                    store: store
                )

            case .describeFeature, .reviewImplementationPlan, .followups:
                break // These are interactive steps handled via UI
            }

            reloadSelectedJob()
            state = .idle
        } catch {
            state = .error(error)
        }
    }

    func goToStep(_ index: Int) async {
        guard let job = selectedJob, let store else { return }
        selectedStepIndex = index

        // Mark subsequent steps stale if going back
        if index < job.currentStepIndex {
            do {
                try manageGuidelinesUseCase.markSubsequentStepsStale(
                    jobId: job.jobId,
                    fromStepIndex: index,
                    store: store
                )
                reloadSelectedJob()
            } catch {
                state = .error(error)
            }
        }
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
