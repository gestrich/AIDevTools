import ArchitecturePlannerService
import Foundation
import SwiftData

/// Validates that the implementation plan covers all requirements and has guideline mappings.
public struct ChecklistValidationUseCase: Sendable {

    public struct Options: Sendable {
        public let jobId: UUID

        public init(jobId: UUID) {
            self.jobId = jobId
        }
    }

    public struct Result: Sendable {
        public let requirementsCovered: Int
        public let requirementsTotal: Int
        public let componentsWithMappings: Int
        public let componentsTotal: Int

        public init(requirementsCovered: Int, requirementsTotal: Int, componentsWithMappings: Int, componentsTotal: Int) {
            self.requirementsCovered = requirementsCovered
            self.requirementsTotal = requirementsTotal
            self.componentsWithMappings = componentsWithMappings
            self.componentsTotal = componentsTotal
        }
    }

    public enum Progress: Sendable {
        case validating
        case validated
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

        onProgress?(.validating)

        let requirements = job.requirements
        let components = job.implementationComponents

        let requirementsCovered = requirements.filter { !$0.implementationComponents.isEmpty }.count
        let componentsWithMappings = components.filter { !$0.guidelineMappings.isEmpty }.count

        let step = job.processSteps.first { $0.stepIndex == ArchitecturePlannerStep.checklistValidation.rawValue }
        step?.status = "completed"
        step?.completedAt = Date()
        step?.summary = "Validated: \(requirementsCovered)/\(requirements.count) requirements covered, \(componentsWithMappings)/\(components.count) components mapped"
        job.currentStepIndex = max(job.currentStepIndex, ArchitecturePlannerStep.buildImplementationModel.rawValue)
        job.updatedAt = Date()

        try context.save()
        onProgress?(.validated)

        return Result(
            requirementsCovered: requirementsCovered,
            requirementsTotal: requirements.count,
            componentsWithMappings: componentsWithMappings,
            componentsTotal: components.count
        )
    }
}
