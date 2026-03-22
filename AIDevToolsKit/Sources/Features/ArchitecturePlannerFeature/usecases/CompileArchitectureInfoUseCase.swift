import ArchitecturePlannerService
import ClaudeCLISDK
import Foundation
import SwiftData

/// Identifies application layers and loads high-level guideline overviews.
public struct CompileArchitectureInfoUseCase: Sendable {

    public struct Options: Sendable {
        public let jobId: UUID
        public let repoPath: String

        public init(jobId: UUID, repoPath: String) {
            self.jobId = jobId
            self.repoPath = repoPath
        }
    }

    public struct Result: Sendable {
        public let layersSummary: String
        public let guidelinesLoaded: Int

        public init(layersSummary: String, guidelinesLoaded: Int) {
            self.layersSummary = layersSummary
            self.guidelinesLoaded = guidelinesLoaded
        }
    }

    public enum Progress: Sendable {
        case loadingGuidelines
        case identifyingLayers
        case completed
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

        onProgress?(.loadingGuidelines)

        // Load existing guidelines for this repo
        let repoName = job.repoName
        let guidelinePredicate = #Predicate<Guideline> { $0.repoName == repoName }
        let guidelineDescriptor = FetchDescriptor<Guideline>(predicate: guidelinePredicate)
        let guidelines = try context.fetch(guidelineDescriptor)

        onProgress?(.identifyingLayers)

        let requirementsSummary = job.requirements.sorted(by: { $0.sortOrder < $1.sortOrder })
            .map { "- \($0.summary)" }
            .joined(separator: "\n")

        let guidelinesSummary = guidelines.map { "- \($0.title): \($0.highLevelOverview)" }
            .joined(separator: "\n")

        let prompt = """
        You are analyzing an application's architecture to plan a new feature.

        Requirements:
        \(requirementsSummary)

        Known architectural guidelines:
        \(guidelinesSummary.isEmpty ? "(none loaded yet)" : guidelinesSummary)

        Analyze the repository structure and identify:
        1. The application's architectural layers
        2. Which guidelines are relevant to these requirements
        3. A summary of the architectural context

        Return a concise summary.
        """

        let schema = """
        {"type":"object","properties":{"layersSummary":{"type":"string","description":"Summary of identified layers and architecture"},"relevantGuidelineCount":{"type":"integer","description":"Number of relevant guidelines identified"}},"required":["layersSummary","relevantGuidelineCount"]}
        """

        var command = Claude(prompt: prompt)
        command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
        command.jsonSchema = schema
        command.printMode = true

        struct ArchInfoResponse: Codable {
            let layersSummary: String
            let relevantGuidelineCount: Int
        }

        let output = try await claudeClient.runStructured(
            ArchInfoResponse.self,
            command: command,
            workingDirectory: options.repoPath
        )

        // Update step
        let step = job.processSteps.first { $0.stepIndex == ArchitecturePlannerStep.compileArchitectureInfo.rawValue }
        step?.status = "completed"
        step?.completedAt = Date()
        step?.summary = output.value.layersSummary.prefix(200).description
        job.currentStepIndex = max(job.currentStepIndex, ArchitecturePlannerStep.planAcrossLayers.rawValue)
        job.updatedAt = Date()

        try context.save()
        onProgress?(.completed)

        return Result(
            layersSummary: output.value.layersSummary,
            guidelinesLoaded: guidelines.count
        )
    }
}
