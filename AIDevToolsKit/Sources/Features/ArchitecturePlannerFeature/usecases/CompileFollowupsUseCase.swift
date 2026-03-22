import ArchitecturePlannerService
import Foundation
import SwiftData

/// Collects unclear flags and open questions into followup items.
public struct CompileFollowupsUseCase: Sendable {

    public struct Options: Sendable {
        public let jobId: UUID

        public init(jobId: UUID) {
            self.jobId = jobId
        }
    }

    public struct Result: Sendable {
        public let followupsCreated: Int

        public init(followupsCreated: Int) {
            self.followupsCreated = followupsCreated
        }
    }

    public enum Progress: Sendable {
        case collecting
        case collected(count: Int)
        case saved
    }

    public init() {}

    @MainActor
    public func run(
        _ options: Options,
        store: ArchitecturePlannerStore,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) throws -> Result {
        let context = store.createContext()

        let jobId = options.jobId
        let predicate = #Predicate<PlanningJob> { $0.jobId == jobId }
        let descriptor = FetchDescriptor<PlanningJob>(predicate: predicate)
        guard let job = try context.fetch(descriptor).first else {
            throw ArchitecturePlannerError.jobNotFound(jobId)
        }

        onProgress?(.collecting)

        var followupCount = 0
        for component in job.implementationComponents {
            for flag in component.unclearFlags where !flag.isPromotedToFollowup {
                let followup = FollowupItem(
                    summary: "Unclear: \(flag.guidelineTitle) — \(flag.ambiguityDescription)",
                    details: "Choice made: \(flag.choiceMade)\nComponent: \(component.summary)"
                )
                followup.job = job
                flag.isPromotedToFollowup = true
                followupCount += 1
            }
        }

        onProgress?(.collected(count: followupCount))

        let step = job.processSteps.first { $0.stepIndex == ArchitecturePlannerStep.followups.rawValue }
        step?.status = "completed"
        step?.completedAt = Date()
        step?.summary = "Compiled \(followupCount) followup items from unclear flags"
        job.updatedAt = Date()

        try context.save()
        onProgress?(.saved)

        return Result(followupsCreated: followupCount)
    }
}
