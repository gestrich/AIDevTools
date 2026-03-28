import AIOutputSDK
import ArchitecturePlannerService
import Foundation

public struct RunPlanningStepUseCase {

    private let compileArchInfo: CompileArchitectureInfoUseCase
    private let compileFollowups: CompileFollowupsUseCase
    private let execute: ExecuteImplementationUseCase
    private let formRequirements: FormRequirementsUseCase
    private let generateReport: GenerateReportUseCase
    private let planAcrossLayers: PlanAcrossLayersUseCase
    private let scoreConformance: ScoreConformanceUseCase

    public init(client: any AIClient) {
        self.compileArchInfo = CompileArchitectureInfoUseCase(client: client)
        self.compileFollowups = CompileFollowupsUseCase(client: client)
        self.execute = ExecuteImplementationUseCase(client: client)
        self.formRequirements = FormRequirementsUseCase(client: client)
        self.generateReport = GenerateReportUseCase()
        self.planAcrossLayers = PlanAcrossLayersUseCase(client: client)
        self.scoreConformance = ScoreConformanceUseCase(client: client)
    }

    public struct Options: Sendable {
        public let jobId: UUID
        public let repoPath: String
        public let step: ArchitecturePlannerStep

        public init(jobId: UUID, repoPath: String, step: ArchitecturePlannerStep) {
            self.jobId = jobId
            self.repoPath = repoPath
            self.step = step
        }
    }

    @MainActor
    public func run(
        _ options: Options,
        store: ArchitecturePlannerStore,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws {
        switch options.step {
        case .buildImplementationModel, .checklistValidation:
            _ = try await scoreConformance.run(
                ScoreConformanceUseCase.Options(jobId: options.jobId, repoPath: options.repoPath),
                store: store,
                onOutput: onOutput
            )
        case .compileArchitectureInfo:
            _ = try await compileArchInfo.run(
                CompileArchitectureInfoUseCase.Options(jobId: options.jobId, repoPath: options.repoPath),
                store: store,
                onOutput: onOutput
            )
        case .describeFeature, .reviewImplementationPlan:
            break
        case .executeImplementation:
            _ = try await execute.run(
                ExecuteImplementationUseCase.Options(jobId: options.jobId, repoPath: options.repoPath),
                store: store,
                onOutput: onOutput
            )
        case .finalReport:
            _ = try generateReport.run(
                GenerateReportUseCase.Options(jobId: options.jobId),
                store: store
            )
        case .followups:
            _ = try await compileFollowups.run(
                CompileFollowupsUseCase.Options(jobId: options.jobId, repoPath: options.repoPath),
                store: store,
                onOutput: onOutput
            )
        case .formRequirements:
            _ = try await formRequirements.run(
                FormRequirementsUseCase.Options(jobId: options.jobId, repoPath: options.repoPath),
                store: store,
                onOutput: onOutput
            )
        case .planAcrossLayers:
            _ = try await planAcrossLayers.run(
                PlanAcrossLayersUseCase.Options(jobId: options.jobId, repoPath: options.repoPath),
                store: store,
                onOutput: onOutput
            )
        }
    }
}
