import ArchitecturePlannerService
import ClaudeCLISDK
import Foundation
import SwiftData

/// Extracts discrete requirements from the user's feature description using AI.
public struct FormRequirementsUseCase: Sendable {

    public struct Options: Sendable {
        public let jobId: UUID
        public let repoPath: String

        public init(jobId: UUID, repoPath: String) {
            self.jobId = jobId
            self.repoPath = repoPath
        }
    }

    public struct Result: Sendable {
        public let requirements: [RequirementDTO]

        public init(requirements: [RequirementDTO]) {
            self.requirements = requirements
        }
    }

    public struct RequirementDTO: Codable, Sendable {
        public let summary: String
        public let details: String
    }

    public enum Progress: Sendable {
        case extracting
        case extracted(count: Int)
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

        guard let request = job.request else {
            throw ArchitecturePlannerError.noRequest(jobId)
        }

        onProgress?(.extracting)

        let prompt = """
        You are analyzing a feature request to extract discrete, testable requirements.

        Feature request:
        "\(request.text)"

        Extract individual requirements from this description. Each requirement should be:
        - A single, discrete capability or behavior
        - Testable and verifiable
        - Clear and unambiguous

        Return the requirements as a JSON array.
        """

        let schema = """
        {"type":"object","properties":{"requirements":{"type":"array","items":{"type":"object","properties":{"summary":{"type":"string","description":"One-line requirement summary"},"details":{"type":"string","description":"Detailed description of the requirement"}},"required":["summary","details"]}}},"required":["requirements"]}
        """

        var command = Claude(prompt: prompt)
        command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
        command.jsonSchema = schema

        struct RequirementsResponse: Codable {
            let requirements: [RequirementDTO]
        }

        let output = try await claudeClient.runStructured(
            RequirementsResponse.self,
            command: command,
            workingDirectory: options.repoPath
        )

        let dtos = output.value.requirements
        onProgress?(.extracted(count: dtos.count))

        // Remove existing requirements
        for req in job.requirements {
            context.delete(req)
        }

        // Insert new requirements
        for (index, dto) in dtos.enumerated() {
            let req = Requirement(
                summary: dto.summary,
                details: dto.details,
                sortOrder: index
            )
            req.job = job
        }

        // Update process step
        let step = job.processSteps.first { $0.stepIndex == ArchitecturePlannerStep.formRequirements.rawValue }
        step?.status = "completed"
        step?.completedAt = Date()
        step?.summary = "Extracted \(dtos.count) requirements"
        job.currentStepIndex = max(job.currentStepIndex, ArchitecturePlannerStep.compileArchitectureInfo.rawValue)
        job.updatedAt = Date()

        try context.save()
        onProgress?(.saved)

        return Result(requirements: dtos)
    }
}

// MARK: - Errors

public enum ArchitecturePlannerError: Error, LocalizedError {
    case jobNotFound(UUID)
    case noRequest(UUID)
    case stepNotReady(String)

    public var errorDescription: String? {
        switch self {
        case .jobNotFound(let id): return "Planning job not found: \(id)"
        case .noRequest(let id): return "No request found for job: \(id)"
        case .stepNotReady(let step): return "Step not ready: \(step)"
        }
    }
}
