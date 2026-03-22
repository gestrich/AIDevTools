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
        public let guidelinesApplied: [GuidelineReference]
        public let requirementIndices: [Int]
    }

    public struct GuidelineReference: Codable, Sendable {
        public let title: String
        public let reason: String
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

        onProgress?(.planning)

        // Load guidelines for this repo
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

        let requirements = job.requirements.sorted(by: { $0.sortOrder < $1.sortOrder })
        let reqList = requirements.enumerated().map { "\($0.offset): \($0.element.summary)" }.joined(separator: "\n")

        let archSummary = job.processSteps
            .first { $0.stepIndex == ArchitecturePlannerStep.compileArchitectureInfo.rawValue }?
            .summary ?? ""

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

        let guidelinesSection = guidelines.map { guideline in
            "- **\(guideline.title)**: \(guideline.highLevelOverview)"
        }.joined(separator: "\n")

        let prompt = """
        You are planning implementation across architectural layers for a feature.

        ## ARCHITECTURE.md
        \(architectureSection)

        ## Architecture Analysis (from prior step)
        \(archSummary)

        ## Requirements
        \(reqList)

        ## Architectural Guidelines
        \(guidelinesSection.isEmpty ? "(no guidelines loaded)" : guidelinesSection)

        ## Task
        For each requirement, determine:
        1. Which architectural layer(s) from ARCHITECTURE.md it belongs to
        2. Which module(s) it affects
        3. What files need to be created or modified
        4. Any tradeoffs in the placement decision
        5. Which guidelines from the list above influenced the placement decision and why

        Group related changes into implementation components. Each component should be a discrete, implementable change.

        Use actual layer names from ARCHITECTURE.md and reference specific guideline titles when explaining placement decisions. Each component must include a guidelinesApplied array listing the guideline titles that influenced that component's placement and the reason each guideline applies.

        Return the components as a JSON array with requirementIndices linking back to the requirements above.
        """

        let schema = """
        {"type":"object","properties":{"components":{"type":"array","items":{"type":"object","properties":{"summary":{"type":"string"},"details":{"type":"string"},"filePaths":{"type":"array","items":{"type":"string"}},"layerName":{"type":"string"},"moduleName":{"type":"string"},"tradeoffs":{"type":"string"},"guidelinesApplied":{"type":"array","items":{"type":"object","properties":{"title":{"type":"string"},"reason":{"type":"string"}},"required":["title","reason"]}},"requirementIndices":{"type":"array","items":{"type":"integer"}}},"required":["summary","details","filePaths","layerName","moduleName","tradeoffs","guidelinesApplied","requirementIndices"]}}},"required":["components"]}
        """

        var command = Claude(prompt: prompt)
        command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
        command.jsonSchema = schema
        command.printMode = true
        command.verbose = true

        struct PlanResponse: Codable {
            let components: [ComponentDTO]
        }

        let output = try await claudeClient.runStructured(
            PlanResponse.self,
            command: command,
            workingDirectory: options.repoPath,
            onFormattedOutput: onOutput
        )

        let dtos = output.value.components
        onProgress?(.planned(componentCount: dtos.count))

        // Clear existing components
        for comp in job.implementationComponents {
            context.delete(comp)
        }

        // Build a lookup of guidelines by title for linking
        let guidelinesByTitle = Dictionary(
            guidelines.map { ($0.title.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

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

            // Create GuidelineMappings from the guidelines Claude referenced
            for ref in dto.guidelinesApplied {
                if let guideline = guidelinesByTitle[ref.title.lowercased()] {
                    let mapping = GuidelineMapping(matchReason: ref.reason)
                    mapping.guideline = guideline
                    mapping.component = comp
                    context.insert(mapping)
                }
            }
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
