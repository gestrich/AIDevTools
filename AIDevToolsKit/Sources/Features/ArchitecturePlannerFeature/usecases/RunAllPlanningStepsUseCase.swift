import AIOutputSDK
import ArchitecturePlannerService
import Foundation
import UseCaseSDK

public struct RunAllPlanningStepsUseCase: UseCase {

    private let manageGuidelines: ManageGuidelinesUseCase
    private let runStep: RunPlanningStepUseCase

    public init(client: any AIClient) {
        self.manageGuidelines = ManageGuidelinesUseCase()
        self.runStep = RunPlanningStepUseCase(client: client)
    }

    public struct Options: Sendable {
        public let jobId: UUID
        public let repoPath: String

        public init(jobId: UUID, repoPath: String) {
            self.jobId = jobId
            self.repoPath = repoPath
        }
    }

    @MainActor
    public func run(
        _ options: Options,
        store: ArchitecturePlannerStore,
        outputStore: AIOutputStore?,
        onStepStart: (@Sendable (String) -> Void)? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws {
        while let job = try manageGuidelines.getJob(jobId: options.jobId, store: store),
              let step = ArchitecturePlannerStep(rawValue: job.currentStepIndex) {
            onStepStart?(step.name)
            let stepOptions = RunPlanningStepUseCase.Options(
                jobId: options.jobId,
                repoPath: options.repoPath,
                step: step
            )
            if let outputStore {
                let session = AIRunSession(key: "\(options.jobId.uuidString)/\(step.rawValue)", store: outputStore)
                try await session.run(onOutput: onOutput) { outputHandler in
                    try await self.runStep.run(stepOptions, store: store, onOutput: outputHandler)
                }
            } else {
                try await runStep.run(stepOptions, store: store, onOutput: onOutput)
            }
        }
    }
}
