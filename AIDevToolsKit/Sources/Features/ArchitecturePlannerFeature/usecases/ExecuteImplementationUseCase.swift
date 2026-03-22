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

    struct DecisionDTO: Codable {
        let componentIndex: Int
        let guidelineTitle: String
        let decision: String
        let rationale: String
        let wasSkipped: Bool
    }

    struct UnclearFlagDTO: Codable {
        let componentIndex: Int
        let guidelineTitle: String
        let ambiguityDescription: String
        let choiceMade: String
    }

    struct PhaseResponse: Codable {
        let decisions: [DecisionDTO]
        let unclearFlags: [UnclearFlagDTO]
    }

    private let claudeClient: ClaudeCLIClient

    public init(claudeClient: ClaudeCLIClient = ClaudeCLIClient()) {
        self.claudeClient = claudeClient
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

        let components = job.implementationComponents.sorted(by: { $0.sortOrder < $1.sortOrder })
        let repoName = job.repoName

        // Load guidelines
        let guidelinePredicate = #Predicate<Guideline> { $0.repoName == repoName }
        let guidelineDescriptor = FetchDescriptor<Guideline>(predicate: guidelinePredicate)
        let guidelines = try context.fetch(guidelineDescriptor)

        let guidelinesSection = guidelines.map { guideline in
            "- **\(guideline.title)**: \(guideline.highLevelOverview)"
        }.joined(separator: "\n")

        var totalDecisions = 0

        // Group components by phase
        let phaseGroups = Dictionary(grouping: components) { $0.phaseNumber }
        let sortedPhases = phaseGroups.keys.sorted()

        for (phaseIdx, phaseNum) in sortedPhases.enumerated() {
            guard let phaseComponents = phaseGroups[phaseNum] else { continue }

            let phaseSummary = phaseComponents.map { $0.summary }.joined(separator: ", ")
            onProgress?(.startingPhase(index: phaseIdx, summary: phaseSummary))

            let componentDetails = phaseComponents.enumerated().map { idx, comp in
                var detail = "\(idx): \(comp.summary)\n   Files: \(comp.filePaths.joined(separator: ", "))\n   Layer: \(comp.layerName)/\(comp.moduleName)\n   Details: \(comp.details)"
                let guidelineRefs = comp.guidelineMappings.compactMap { $0.guideline?.title }
                if !guidelineRefs.isEmpty {
                    detail += "\n   Applicable guidelines: \(guidelineRefs.joined(separator: ", "))"
                }
                return detail
            }.joined(separator: "\n\n")

            let prompt = """
            You are evaluating implementation decisions for phase \(phaseNum) of an architecture plan.

            ## Components in This Phase
            \(componentDetails)

            ## Architectural Guidelines
            \(guidelinesSection.isEmpty ? "(no guidelines loaded)" : guidelinesSection)

            ## Task
            For each component, evaluate the implementation against applicable guidelines and produce decisions:

            1. For each applicable guideline on each component, record a decision:
               - What action should be taken (e.g., "Create protocol in Services layer", "Add observable model with enum-based state")
               - Which guideline drove the decision and why
               - Whether implementation should be skipped (e.g., guideline doesn't apply to this context)

            2. If any guideline is ambiguous, contradictory, or insufficient for a component, flag it:
               - Describe what was unclear
               - State what choice was made despite the ambiguity

            Reference actual guideline titles from the list above. Each component should have at least one decision.
            """

            let schema = """
            {"type":"object","properties":{"decisions":{"type":"array","items":{"type":"object","properties":{"componentIndex":{"type":"integer"},"guidelineTitle":{"type":"string"},"decision":{"type":"string"},"rationale":{"type":"string"},"wasSkipped":{"type":"boolean"}},"required":["componentIndex","guidelineTitle","decision","rationale","wasSkipped"]}},"unclearFlags":{"type":"array","items":{"type":"object","properties":{"componentIndex":{"type":"integer"},"guidelineTitle":{"type":"string"},"ambiguityDescription":{"type":"string"},"choiceMade":{"type":"string"}},"required":["componentIndex","guidelineTitle","ambiguityDescription","choiceMade"]}}},"required":["decisions","unclearFlags"]}
            """

            var command = Claude(prompt: prompt)
            command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
            command.jsonSchema = schema
            command.printMode = true
            command.verbose = true

            let output = try await claudeClient.runStructured(
                PhaseResponse.self,
                command: command,
                workingDirectory: options.repoPath,
                onFormattedOutput: onOutput
            )

            onProgress?(.phaseCompleted(index: phaseIdx))
            onProgress?(.evaluating(index: phaseIdx))

            let response = output.value

            // Record decisions
            for dto in response.decisions {
                guard dto.componentIndex >= 0 && dto.componentIndex < phaseComponents.count else { continue }
                let comp = phaseComponents[dto.componentIndex]
                let decision = PhaseDecision(
                    guidelineTitle: dto.guidelineTitle,
                    decision: dto.decision,
                    rationale: dto.rationale,
                    phaseNumber: phaseNum,
                    wasSkipped: dto.wasSkipped
                )
                decision.component = comp
                totalDecisions += 1
            }

            // Record unclear flags
            for dto in response.unclearFlags {
                guard dto.componentIndex >= 0 && dto.componentIndex < phaseComponents.count else { continue }
                let comp = phaseComponents[dto.componentIndex]
                let flag = UnclearFlag(
                    guidelineTitle: dto.guidelineTitle,
                    ambiguityDescription: dto.ambiguityDescription,
                    choiceMade: dto.choiceMade
                )
                flag.component = comp
            }

            try context.save()
        }

        let unclearCount = components.flatMap { $0.unclearFlags }.count

        // Update step
        let step = job.processSteps.first { $0.stepIndex == ArchitecturePlannerStep.executeImplementation.rawValue }
        step?.status = "completed"
        step?.completedAt = Date()
        step?.summary = "Executed \(sortedPhases.count) phases, recorded \(totalDecisions) decisions, \(unclearCount) unclear flags"
        job.currentStepIndex = max(job.currentStepIndex, ArchitecturePlannerStep.finalReport.rawValue)
        job.updatedAt = Date()

        try context.save()
        onProgress?(.allCompleted)

        return Result(phasesExecuted: sortedPhases.count, decisionsRecorded: totalDecisions)
    }
}
