import ArchitecturePlannerService
import ClaudeCLISDK
import Foundation
import SwiftData

/// Scores each implementation component against applicable guidelines.
public struct ScoreConformanceUseCase: Sendable {

    public struct Options: Sendable {
        public let jobId: UUID
        public let repoPath: String

        public init(jobId: UUID, repoPath: String) {
            self.jobId = jobId
            self.repoPath = repoPath
        }
    }

    public struct Result: Sendable {
        public let averageScore: Double
        public let mappingsCreated: Int

        public init(averageScore: Double, mappingsCreated: Int) {
            self.averageScore = averageScore
            self.mappingsCreated = mappingsCreated
        }
    }

    public struct MappingDTO: Codable, Sendable {
        public let componentIndex: Int
        public let guidelineTitle: String
        public let matchReason: String
        public let conformanceScore: Int
        public let scoreRationale: String
    }

    public enum Progress: Sendable {
        case scoring
        case scored(mappingCount: Int)
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

        let components = job.implementationComponents.sorted(by: { $0.sortOrder < $1.sortOrder })
        let repoName = job.repoName

        // Load guidelines
        let guidelinePredicate = #Predicate<Guideline> { $0.repoName == repoName }
        let guidelineDescriptor = FetchDescriptor<Guideline>(predicate: guidelinePredicate)
        let guidelines = try context.fetch(guidelineDescriptor)

        guard !components.isEmpty else {
            return Result(averageScore: 0, mappingsCreated: 0)
        }

        onProgress?(.scoring)

        let componentList = components.enumerated().map { "\($0.offset): \($0.element.summary) [\($0.element.layerName)/\($0.element.moduleName)]" }
            .joined(separator: "\n")

        let guidelineList = guidelines.map { "- \($0.title): \($0.body.prefix(200))" }
            .joined(separator: "\n")

        let prompt = """
        Score each implementation component against applicable architectural guidelines.

        Components:
        \(componentList)

        Guidelines:
        \(guidelineList.isEmpty ? "(no guidelines loaded)" : guidelineList)

        For each component, identify which guidelines apply, why they match, and score conformance 1-10.
        If no guidelines are loaded, evaluate against general software architecture best practices.

        Return mappings as a JSON array.
        """

        let schema = """
        {"type":"object","properties":{"mappings":{"type":"array","items":{"type":"object","properties":{"componentIndex":{"type":"integer"},"guidelineTitle":{"type":"string"},"matchReason":{"type":"string"},"conformanceScore":{"type":"integer"},"scoreRationale":{"type":"string"}},"required":["componentIndex","guidelineTitle","matchReason","conformanceScore","scoreRationale"]}}},"required":["mappings"]}
        """

        var command = Claude(prompt: prompt)
        command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
        command.jsonSchema = schema

        struct ScoreResponse: Codable {
            let mappings: [MappingDTO]
        }

        let output = try await claudeClient.runStructured(
            ScoreResponse.self,
            command: command,
            workingDirectory: options.repoPath
        )

        let dtos = output.value.mappings
        onProgress?(.scored(mappingCount: dtos.count))

        // Clear existing mappings
        for comp in components {
            for mapping in comp.guidelineMappings {
                context.delete(mapping)
            }
        }

        // Create new mappings
        var totalScore = 0
        for dto in dtos {
            guard dto.componentIndex >= 0 && dto.componentIndex < components.count else { continue }
            let comp = components[dto.componentIndex]

            // Find or reference guideline
            let guideline = guidelines.first { $0.title == dto.guidelineTitle }

            let mapping = GuidelineMapping(
                matchReason: dto.matchReason,
                conformanceScore: dto.conformanceScore,
                scoreRationale: dto.scoreRationale
            )
            mapping.component = comp
            mapping.guideline = guideline
            totalScore += dto.conformanceScore
        }

        let avgScore = dtos.isEmpty ? 0.0 : Double(totalScore) / Double(dtos.count)

        // Update step
        let step = job.processSteps.first { $0.stepIndex == ArchitecturePlannerStep.buildImplementationModel.rawValue }
        step?.status = "completed"
        step?.completedAt = Date()
        step?.summary = "Scored \(dtos.count) mappings, avg: \(String(format: "%.1f", avgScore))/10"
        job.currentStepIndex = max(job.currentStepIndex, ArchitecturePlannerStep.reviewImplementationPlan.rawValue)
        job.updatedAt = Date()

        try context.save()
        onProgress?(.saved)

        return Result(averageScore: avgScore, mappingsCreated: dtos.count)
    }
}
