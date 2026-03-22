import ArchitecturePlannerService
import Foundation
import SwiftData

/// Creates a new PlanningJob with default process steps and an initial request.
public struct CreatePlanningJobUseCase: Sendable {

    public struct Options: Sendable {
        public let repoName: String
        public let repoPath: String
        public let featureDescription: String

        public init(repoName: String, repoPath: String, featureDescription: String) {
            self.repoName = repoName
            self.repoPath = repoPath
            self.featureDescription = featureDescription
        }
    }

    public struct Result: Sendable {
        public let jobId: UUID

        public init(jobId: UUID) {
            self.jobId = jobId
        }
    }

    public init() {}

    @MainActor
    public func run(_ options: Options, store: ArchitecturePlannerStore) throws -> Result {
        let context = store.createContext()

        let job = PlanningJob(
            repoName: options.repoName,
            repoPath: options.repoPath
        )

        let request = ArchitectureRequest(text: options.featureDescription)
        job.request = request

        let steps = ArchitecturePlannerStep.defaultSteps()
        for step in steps {
            step.job = job
        }
        job.processSteps = steps

        // Mark first step as completed since we have the description
        if let firstStep = steps.first {
            firstStep.status = "completed"
            firstStep.completedAt = Date()
            firstStep.summary = "Feature described: \(options.featureDescription.prefix(100))"
        }
        job.currentStepIndex = 1

        context.insert(job)
        try context.save()

        return Result(jobId: job.jobId)
    }
}
