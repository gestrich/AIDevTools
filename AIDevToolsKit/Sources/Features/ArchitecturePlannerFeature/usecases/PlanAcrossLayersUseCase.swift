import ArchitecturePlannerService
import ClaudeCLISDK
import Foundation
import SwiftData

/// Determines where each piece of logic belongs across architectural layers.
public struct PlanAcrossLayersUseCase: Sendable {

    public struct Options: Sendable {
        public let jobId: UUID
        public let repoPath: String

        public init(jobId: UUID, repoPath: String) {
            self.jobId = jobId
            self.repoPath = repoPath
        }
    }

    public struct Result: Sendable {
        public let componentCount: Int

        public init(componentCount: Int) {
            self.componentCount = componentCount
        }
    }

    public struct ComponentDTO: Codable, Sendable {
        public let summary: String
        public let details: String
        public let filePaths: [String]
        public let layerName: String
        public let moduleName: String
        public let tradeoffs: String
        public let requirementIndices: [Int]
    }

    public enum Progress: Sendable {
        case planning
        case planned(componentCount: Int)
        case saved
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

        onProgress?(.planning)

        let requirements = job.requirements.sorted(by: { $0.sortOrder < $1.sortOrder })
        let reqList = requirements.enumerated().map { "\($0.offset): \($0.element.summary)" }.joined(separator: "\n")

        let archSummary = job.processSteps
            .first { $0.stepIndex == ArchitecturePlannerStep.compileArchitectureInfo.rawValue }?
            .summary ?? ""

        let prompt = """
        You are planning implementation across architectural layers for a feature.

        Requirements:
        \(reqList)

        Architecture context:
        \(archSummary)

        For each requirement, determine:
        1. Which architectural layer(s) it belongs to
        2. Which module(s) it affects
        3. What files need to be created or modified
        4. Any tradeoffs in the placement decision

        Group related changes into implementation components. Each component should be a discrete, implementable change.

        Return the components as a JSON array with requirementIndices linking back to the requirements above.
        """

        let schema = """
        {"type":"object","properties":{"components":{"type":"array","items":{"type":"object","properties":{"summary":{"type":"string"},"details":{"type":"string"},"filePaths":{"type":"array","items":{"type":"string"}},"layerName":{"type":"string"},"moduleName":{"type":"string"},"tradeoffs":{"type":"string"},"requirementIndices":{"type":"array","items":{"type":"integer"}}},"required":["summary","details","filePaths","layerName","moduleName","tradeoffs","requirementIndices"]}}},"required":["components"]}
        """

        var command = Claude(prompt: prompt)
        command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
        command.jsonSchema = schema
        command.printMode = true

        struct PlanResponse: Codable {
            let components: [ComponentDTO]
        }

        let output = try await claudeClient.runStructured(
            PlanResponse.self,
            command: command,
            workingDirectory: options.repoPath
        )

        let dtos = output.value.components
        onProgress?(.planned(componentCount: dtos.count))

        // Clear existing components
        for comp in job.implementationComponents {
            context.delete(comp)
        }

        // Insert new components
        for (index, dto) in dtos.enumerated() {
            let comp = ImplementationComponent(
                summary: dto.summary,
                details: dto.details,
                filePaths: dto.filePaths,
                layerName: dto.layerName,
                moduleName: dto.moduleName,
                tradeoffs: dto.tradeoffs,
                sortOrder: index
            )
            comp.job = job

            // Link requirements
            let linkedReqs = dto.requirementIndices.compactMap { idx -> Requirement? in
                guard idx >= 0 && idx < requirements.count else { return nil }
                return requirements[idx]
            }
            comp.requirements = linkedReqs
        }

        // Update step
        let step = job.processSteps.first { $0.stepIndex == ArchitecturePlannerStep.planAcrossLayers.rawValue }
        step?.status = "completed"
        step?.completedAt = Date()
        step?.summary = "Planned \(dtos.count) implementation components"
        job.currentStepIndex = max(job.currentStepIndex, ArchitecturePlannerStep.checklistValidation.rawValue)
        job.updatedAt = Date()

        try context.save()
        onProgress?(.saved)

        return Result(componentCount: dtos.count)
    }
}
