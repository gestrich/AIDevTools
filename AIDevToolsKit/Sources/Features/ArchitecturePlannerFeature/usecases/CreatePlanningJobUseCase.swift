import ArchitecturePlannerService
import Foundation
import SwiftData
import UseCaseSDK

/// Creates a new PlanningJob with default process steps and an initial request.
public struct CreatePlanningJobUseCase: UseCase {

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

    public struct RunAndListResult {
        public let jobId: UUID
        public let jobs: [PlanningJob]

        public init(jobId: UUID, jobs: [PlanningJob]) {
            self.jobId = jobId
            self.jobs = jobs
        }
    }

    public init() {}

    @MainActor
    public func runAndListJobs(_ options: Options, store: ArchitecturePlannerStore) throws -> RunAndListResult {
        let result = try run(options, store: store)
        let jobs = try ManageGuidelinesUseCase().listJobs(repoName: options.repoName, store: store)
        return RunAndListResult(jobId: result.jobId, jobs: jobs)
    }

    @MainActor
    public func run(_ options: Options, store: ArchitecturePlannerStore) throws -> Result {
        // Seed guidelines if none exist yet
        let seedUseCase = SeedGuidelinesUseCase()
        _ = try seedUseCase.run(
            SeedGuidelinesUseCase.Options(repoName: options.repoName, repoPath: options.repoPath),
            store: store
        )

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
