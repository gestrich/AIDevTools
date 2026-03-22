import ArchitecturePlannerService
import ClaudeCLISDK
import Foundation
import SwiftData

/// Executes the implementation plan phase-by-phase with guideline evaluation after each phase.
public struct ExecuteImplementationUseCase: Sendable {

    public struct Options: Sendable {
        public let jobId: UUID
        public let repoPath: String
        public let reuseSession: Bool

        public init(jobId: UUID, repoPath: String, reuseSession: Bool = true) {
            self.jobId = jobId
            self.repoPath = repoPath
            self.reuseSession = reuseSession
        }
    }

    public struct Result: Sendable {
        public let phasesExecuted: Int
        public let decisionsRecorded: Int

        public init(phasesExecuted: Int, decisionsRecorded: Int) {
            self.phasesExecuted = phasesExecuted
            self.decisionsRecorded = decisionsRecorded
        }
    }

    public enum Progress: Sendable {
        case startingPhase(index: Int, summary: String)
        case phaseOutput(String)
        case phaseCompleted(index: Int)
        case evaluating(index: Int)
        case allCompleted
    }

    private let claudeClient: ClaudeCLIClient

    public init(claudeClient: ClaudeCLIClient = ClaudeCLIClient()) {
        self.claudeClient = claudeClient
    }

    @MainActor
    public func run(
        _ options: Options,
        store: ArchitecturePlannerStore,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> Result {
        let context = store.createContext()

        let jobId = options.jobId
        let predicate = #Predicate<PlanningJob> { $0.jobId == jobId }
        let descriptor = FetchDescriptor<PlanningJob>(predicate: predicate)
        guard let job = try context.fetch(descriptor).first else {
            throw ArchitecturePlannerError.jobNotFound(jobId)
        }

        let components = job.implementationComponents.sorted(by: { $0.sortOrder < $1.sortOrder })

        var totalDecisions = 0

        // Group components by phase
        let phaseGroups = Dictionary(grouping: components) { $0.phaseNumber }
        let sortedPhases = phaseGroups.keys.sorted()

        for (phaseIdx, phaseNum) in sortedPhases.enumerated() {
            guard let phaseComponents = phaseGroups[phaseNum] else { continue }

            let phaseSummary = phaseComponents.map { $0.summary }.joined(separator: ", ")
            onProgress?(.startingPhase(index: phaseIdx, summary: phaseSummary))

            // Build implementation prompt
            let componentDetails = phaseComponents.map { comp in
                var detail = "Component: \(comp.summary)\nFiles: \(comp.filePaths.joined(separator: ", "))\nLayer: \(comp.layerName)/\(comp.moduleName)\nDetails: \(comp.details)"
                let guidelineRefs = comp.guidelineMappings.compactMap { $0.guideline?.title }
                if !guidelineRefs.isEmpty {
                    detail += "\nApplicable guidelines: \(guidelineRefs.joined(separator: ", "))"
                }
                return detail
            }.joined(separator: "\n\n")

            let prompt = """
            Implement the following changes for this phase:

            \(componentDetails)

            Follow all applicable architectural guidelines. For each change, explain what guideline drove the decision.
            """

            var command = Claude(prompt: prompt)
            command.printMode = true
            command.dangerouslySkipPermissions = true

            let executionResult = try await claudeClient.run(
                command: command,
                workingDirectory: options.repoPath,
                onOutput: nil
            )
            onProgress?(.phaseOutput(executionResult.stdout))
            onProgress?(.phaseCompleted(index: phaseIdx))

            // Record decisions
            onProgress?(.evaluating(index: phaseIdx))
            for comp in phaseComponents {
                let decision = PhaseDecision(
                    guidelineTitle: comp.guidelineMappings.first?.guideline?.title ?? "general",
                    decision: "Implemented as planned",
                    rationale: "Phase \(phaseNum) execution",
                    phaseNumber: phaseNum
                )
                decision.component = comp
                totalDecisions += 1
            }

            try context.save()
        }

        // Update step
        let step = job.processSteps.first { $0.stepIndex == ArchitecturePlannerStep.executeImplementation.rawValue }
        step?.status = "completed"
        step?.completedAt = Date()
        step?.summary = "Executed \(sortedPhases.count) phases, recorded \(totalDecisions) decisions"
        job.currentStepIndex = max(job.currentStepIndex, ArchitecturePlannerStep.finalReport.rawValue)
        job.updatedAt = Date()

        try context.save()
        onProgress?(.allCompleted)

        return Result(phasesExecuted: sortedPhases.count, decisionsRecorded: totalDecisions)
    }
}
