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

        // Read ARCHITECTURE.md from the repo path
        let architectureMDPath = URL(fileURLWithPath: options.repoPath)
            .appendingPathComponent("ARCHITECTURE.md")
        let architectureContent: String
        if FileManager.default.fileExists(atPath: architectureMDPath.path) {
            architectureContent = (try? String(contentsOf: architectureMDPath, encoding: .utf8)) ?? ""
        } else {
            architectureContent = ""
        }

        onProgress?(.identifyingLayers)

        let requirementsSummary = job.requirements.sorted(by: { $0.sortOrder < $1.sortOrder })
            .map { "- \($0.summary)" }
            .joined(separator: "\n")

        let guidelinesSection = guidelines.map { guideline in
            "- **\(guideline.title)**: \(guideline.highLevelOverview)"
        }.joined(separator: "\n")

        let architectureSection: String
        if architectureContent.isEmpty {
            architectureSection = "(No ARCHITECTURE.md found in repo)"
        } else {
            architectureSection = """
            <architecture-document>
            \(architectureContent)
            </architecture-document>
            """
        }

        let prompt = """
        You are analyzing an application's architecture to plan a new feature.

        ## ARCHITECTURE.md
        \(architectureSection)

        ## Requirements
        \(requirementsSummary)

        ## Loaded Architectural Guidelines
        \(guidelinesSection.isEmpty ? "(no guidelines loaded)" : guidelinesSection)

        ## Task
        Based on the ARCHITECTURE.md document and the loaded guidelines, produce:
        1. A summary of the application's architectural layers as described in ARCHITECTURE.md
        2. Which specific layers from the architecture are relevant to the requirements above
        3. Which guidelines apply to these requirements and why
        4. Any architectural constraints or conventions that should influence the implementation

        Be specific — reference actual layer names, guideline titles, and conventions from the documents above.
        """

        let schema = """
        {"type":"object","properties":{"layersSummary":{"type":"string","description":"Detailed summary of identified layers, relevant guidelines, and architectural context drawn from ARCHITECTURE.md and loaded guidelines"},"relevantGuidelineCount":{"type":"integer","description":"Number of guidelines relevant to these requirements"}},"required":["layersSummary","relevantGuidelineCount"]}
        """

        var command = Claude(prompt: prompt)
        command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
        command.jsonSchema = schema
        command.printMode = true
        command.verbose = true

        struct ArchInfoResponse: Codable {
            let layersSummary: String
            let relevantGuidelineCount: Int
        }

        let output = try await claudeClient.runStructured(
            ArchInfoResponse.self,
            command: command,
            workingDirectory: options.repoPath
        )

        // Update step with the full layers summary
        let step = job.processSteps.first { $0.stepIndex == ArchitecturePlannerStep.compileArchitectureInfo.rawValue }
        step?.status = "completed"
        step?.completedAt = Date()
        step?.summary = output.value.layersSummary
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
