import AIOutputSDK
import ArchitecturePlannerService
import Foundation
import SwiftData
import UseCaseSDK

/// Collects unclear flags and open questions into followup items,
/// then uses AI to identify additional deferred work from the implementation plan.
public struct CompileFollowupsUseCase: UseCase {

    public struct Options: Sendable {
        public let jobId: UUID
        public let repoPath: String

        public init(jobId: UUID, repoPath: String) {
            self.jobId = jobId
            self.repoPath = repoPath
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
        case identifyingDeferredWork
        case identified(count: Int)
        case saved
    }

    struct FollowupDTO: Codable {
        let summary: String
        let details: String
    }

    struct FollowupsResponse: Codable {
        let additionalFollowups: [FollowupDTO]
    }

    private let client: any AIClient

    public init(client: any AIClient) {
        self.client = client
    }

    @MainActor
    public func run(
        _ options: Options,
        store: ArchitecturePlannerStore,
        onProgress: (@Sendable (Progress) -> Void)? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> Result {
        let context = store.createContext()

        let jobId = options.jobId
        let predicate = #Predicate<PlanningJob> { $0.jobId == jobId }
        let descriptor = FetchDescriptor<PlanningJob>(predicate: predicate)
        guard let job = try context.fetch(descriptor).first else {
            throw ArchitecturePlannerError.jobNotFound(jobId)
        }

        onProgress?(.collecting)

        // Promote unclear flags to followup items
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
        onProgress?(.identifyingDeferredWork)

        // Use AI to identify additional deferred work
        let additionalCount = try await identifyDeferredWork(job: job, options: options, onOutput: onOutput)
        followupCount += additionalCount

        onProgress?(.identified(count: additionalCount))

        let step = job.processSteps.first { $0.stepIndex == ArchitecturePlannerStep.followups.rawValue }
        step?.status = "completed"
        step?.completedAt = Date()
        step?.summary = "Compiled \(followupCount) followup items from unclear flags and deferred work analysis"
        job.currentStepIndex = max(job.currentStepIndex, ArchitecturePlannerStep.followups.rawValue + 1)
        job.updatedAt = Date()

        try context.save()
        onProgress?(.saved)

        return Result(followupsCreated: followupCount)
    }

    @MainActor
    private func identifyDeferredWork(job: PlanningJob, options: Options, onOutput: (@Sendable (String) -> Void)?) async throws -> Int {
        let components = job.implementationComponents.sorted(by: { $0.sortOrder < $1.sortOrder })
        guard !components.isEmpty else { return 0 }

        let componentSummaries = components.enumerated().map { idx, comp in
            var lines = ["\(idx): \(comp.summary)"]
            lines.append("   Layer: \(comp.layerName)/\(comp.moduleName)")
            lines.append("   Files: \(comp.filePaths.joined(separator: ", "))")
            if !comp.tradeoffs.isEmpty {
                lines.append("   Tradeoffs: \(comp.tradeoffs)")
            }
            let decisions = comp.phaseDecisions.map { d in
                "     - \(d.decision) (guideline: \(d.guidelineTitle), skipped: \(d.wasSkipped))"
            }
            if !decisions.isEmpty {
                lines.append("   Decisions:")
                lines.append(contentsOf: decisions)
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")

        let requirementsSummary = job.requirements.sorted(by: { $0.sortOrder < $1.sortOrder }).map { req in
            "- \(req.summary): \(req.details)"
        }.joined(separator: "\n")

        let prompt = """
        You are reviewing a completed architecture implementation plan to identify deferred work and followup items.

        ## Requirements
        \(requirementsSummary.isEmpty ? "(none)" : requirementsSummary)

        ## Implementation Components and Decisions
        \(componentSummaries)

        ## Task
        Analyze the implementation plan and identify any additional followup items that should be tracked:

        1. Work that was explicitly deferred or skipped during implementation decisions
        2. Integration points between components that need verification
        3. Missing test coverage or documentation needs
        4. Performance considerations that should be revisited
        5. Dependencies on external systems that need coordination

        Only include genuinely actionable followups — not generic advice. If the plan is comprehensive and nothing was deferred, return an empty array.
        """

        let schema = """
        {"type":"object","properties":{"additionalFollowups":{"type":"array","items":{"type":"object","properties":{"summary":{"type":"string"},"details":{"type":"string"}},"required":["summary","details"]}}},"required":["additionalFollowups"]}
        """

        let aiOptions = AIClientOptions(workingDirectory: options.repoPath)

        let output = try await client.runStructured(
            FollowupsResponse.self,
            prompt: prompt,
            jsonSchema: schema,
            options: aiOptions,
            onOutput: onOutput
        )

        var count = 0
        for dto in output.value.additionalFollowups {
            let followup = FollowupItem(
                summary: dto.summary,
                details: dto.details
            )
            followup.job = job
            count += 1
        }

        return count
    }
}
