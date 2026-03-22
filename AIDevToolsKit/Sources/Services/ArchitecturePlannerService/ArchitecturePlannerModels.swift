import Foundation
import SwiftData

// MARK: - PlanningJob

/// Root model representing a single architecture planning job.
@Model
public final class PlanningJob {
    #Unique<PlanningJob>([\.jobId])

    public var jobId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var repoName: String
    public var repoPath: String
    public var currentStepIndex: Int

    @Relationship(deleteRule: .cascade, inverse: \ArchitectureRequest.job)
    public var request: ArchitectureRequest?

    @Relationship(deleteRule: .cascade, inverse: \Requirement.job)
    public var requirements: [Requirement]

    @Relationship(deleteRule: .cascade, inverse: \ImplementationComponent.job)
    public var implementationComponents: [ImplementationComponent]

    @Relationship(deleteRule: .cascade, inverse: \ProcessStep.job)
    public var processSteps: [ProcessStep]

    @Relationship(deleteRule: .cascade, inverse: \FollowupItem.job)
    public var followupItems: [FollowupItem]

    public init(
        jobId: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        repoName: String,
        repoPath: String,
        currentStepIndex: Int = 0
    ) {
        self.jobId = jobId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.repoName = repoName
        self.repoPath = repoPath
        self.currentStepIndex = currentStepIndex
        self.requirements = []
        self.implementationComponents = []
        self.processSteps = []
        self.followupItems = []
    }
}

// MARK: - ArchitectureRequest

/// The user's feature description, updated as iterations occur.
@Model
public final class ArchitectureRequest {
    public var requestId: UUID
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date

    public var job: PlanningJob?

    public init(
        requestId: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.requestId = requestId
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Requirement

/// A discrete requirement extracted from the user's request.
@Model
public final class Requirement {
    public var requirementId: UUID
    public var summary: String
    public var details: String
    public var isApproved: Bool
    public var sortOrder: Int

    public var job: PlanningJob?

    @Relationship(deleteRule: .nullify, inverse: \ImplementationComponent.requirements)
    public var implementationComponents: [ImplementationComponent]

    public init(
        requirementId: UUID = UUID(),
        summary: String,
        details: String = "",
        isApproved: Bool = false,
        sortOrder: Int = 0
    ) {
        self.requirementId = requirementId
        self.summary = summary
        self.details = details
        self.isApproved = isApproved
        self.sortOrder = sortOrder
        self.implementationComponents = []
    }
}

// MARK: - GuidelineCategory

/// A user-defined category for organizing guidelines (e.g. architecture, conventions, swiftui, testing).
@Model
public final class GuidelineCategory {
    #Unique<GuidelineCategory>([\.name, \.repoName])

    public var categoryId: UUID
    public var name: String
    public var repoName: String
    public var summary: String

    @Relationship(deleteRule: .nullify, inverse: \Guideline.categories)
    public var guidelines: [Guideline]

    public init(
        categoryId: UUID = UUID(),
        name: String,
        repoName: String,
        summary: String = ""
    ) {
        self.categoryId = categoryId
        self.name = name
        self.repoName = repoName
        self.summary = summary
        self.guidelines = []
    }
}

// MARK: - Guideline

/// An architectural guideline/rule that governs how code should be written.
/// Shared across planning jobs within a repo.
@Model
public final class Guideline {
    public var guidelineId: UUID
    public var repoName: String
    public var title: String
    public var body: String
    public var filePathGlobs: [String]
    public var descriptionMatchers: [String]
    public var goodExamples: [String]
    public var badExamples: [String]
    public var highLevelOverview: String
    public var createdAt: Date
    public var updatedAt: Date

    public var categories: [GuidelineCategory]

    @Relationship(deleteRule: .cascade, inverse: \GuidelineMapping.guideline)
    public var mappings: [GuidelineMapping]

    public init(
        guidelineId: UUID = UUID(),
        repoName: String,
        title: String,
        body: String = "",
        filePathGlobs: [String] = [],
        descriptionMatchers: [String] = [],
        goodExamples: [String] = [],
        badExamples: [String] = [],
        highLevelOverview: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.guidelineId = guidelineId
        self.repoName = repoName
        self.title = title
        self.body = body
        self.filePathGlobs = filePathGlobs
        self.descriptionMatchers = descriptionMatchers
        self.goodExamples = goodExamples
        self.badExamples = badExamples
        self.highLevelOverview = highLevelOverview
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.categories = []
        self.mappings = []
    }
}

// MARK: - ImplementationComponent

/// A discrete change in the implementation plan — files affected, guidelines, scores.
@Model
public final class ImplementationComponent {
    public var componentId: UUID
    public var summary: String
    public var details: String
    public var filePaths: [String]
    public var layerName: String
    public var moduleName: String
    public var tradeoffs: String
    public var sortOrder: Int
    public var phaseNumber: Int

    public var job: PlanningJob?
    public var requirements: [Requirement]

    @Relationship(deleteRule: .cascade, inverse: \GuidelineMapping.component)
    public var guidelineMappings: [GuidelineMapping]

    @Relationship(deleteRule: .cascade, inverse: \UnclearFlag.component)
    public var unclearFlags: [UnclearFlag]

    @Relationship(deleteRule: .cascade, inverse: \PhaseDecision.component)
    public var phaseDecisions: [PhaseDecision]

    public init(
        componentId: UUID = UUID(),
        summary: String,
        details: String = "",
        filePaths: [String] = [],
        layerName: String = "",
        moduleName: String = "",
        tradeoffs: String = "",
        sortOrder: Int = 0,
        phaseNumber: Int = 0
    ) {
        self.componentId = componentId
        self.summary = summary
        self.details = details
        self.filePaths = filePaths
        self.layerName = layerName
        self.moduleName = moduleName
        self.tradeoffs = tradeoffs
        self.sortOrder = sortOrder
        self.phaseNumber = phaseNumber
        self.requirements = []
        self.guidelineMappings = []
        self.unclearFlags = []
        self.phaseDecisions = []
    }
}

// MARK: - GuidelineMapping

/// Maps a guideline to an implementation component with a conformance score and reasoning.
@Model
public final class GuidelineMapping {
    public var mappingId: UUID
    public var matchReason: String
    public var conformanceScore: Int
    public var scoreRationale: String

    public var guideline: Guideline?
    public var component: ImplementationComponent?

    public init(
        mappingId: UUID = UUID(),
        matchReason: String = "",
        conformanceScore: Int = 0,
        scoreRationale: String = ""
    ) {
        self.mappingId = mappingId
        self.matchReason = matchReason
        self.conformanceScore = conformanceScore
        self.scoreRationale = scoreRationale
    }
}

// MARK: - ProcessStep

/// Represents one step in the architecture-driven flow (e.g. "Requirements Formation", "Plan Across Layers").
@Model
public final class ProcessStep {
    public var stepId: UUID
    public var stepIndex: Int
    public var name: String
    public var status: String  // pending, active, completed, stale
    public var summary: String
    public var completedAt: Date?

    public var job: PlanningJob?

    public init(
        stepId: UUID = UUID(),
        stepIndex: Int,
        name: String,
        status: String = "pending",
        summary: String = "",
        completedAt: Date? = nil
    ) {
        self.stepId = stepId
        self.stepIndex = stepIndex
        self.name = name
        self.status = status
        self.summary = summary
        self.completedAt = completedAt
    }
}

// MARK: - UnclearFlag

/// Flags a guideline that was ambiguous, contradictory, or insufficient during evaluation.
@Model
public final class UnclearFlag {
    public var flagId: UUID
    public var guidelineTitle: String
    public var ambiguityDescription: String
    public var choiceMade: String
    public var isPromotedToFollowup: Bool

    public var component: ImplementationComponent?

    public init(
        flagId: UUID = UUID(),
        guidelineTitle: String,
        ambiguityDescription: String,
        choiceMade: String,
        isPromotedToFollowup: Bool = false
    ) {
        self.flagId = flagId
        self.guidelineTitle = guidelineTitle
        self.ambiguityDescription = ambiguityDescription
        self.choiceMade = choiceMade
        self.isPromotedToFollowup = isPromotedToFollowup
    }
}

// MARK: - PhaseDecision

/// Records a decision made during implementation — what guideline triggered it, what was decided, and why.
@Model
public final class PhaseDecision {
    public var decisionId: UUID
    public var guidelineTitle: String
    public var decision: String
    public var rationale: String
    public var phaseNumber: Int
    public var wasSkipped: Bool

    public var component: ImplementationComponent?

    public init(
        decisionId: UUID = UUID(),
        guidelineTitle: String,
        decision: String,
        rationale: String,
        phaseNumber: Int = 0,
        wasSkipped: Bool = false
    ) {
        self.decisionId = decisionId
        self.guidelineTitle = guidelineTitle
        self.decision = decision
        self.rationale = rationale
        self.phaseNumber = phaseNumber
        self.wasSkipped = wasSkipped
    }
}

// MARK: - FollowupItem

/// Deferred work, open questions, or future improvements tracked as part of the plan.
@Model
public final class FollowupItem {
    public var itemId: UUID
    public var summary: String
    public var details: String
    public var isResolved: Bool

    public var job: PlanningJob?

    public init(
        itemId: UUID = UUID(),
        summary: String,
        details: String = "",
        isResolved: Bool = false
    ) {
        self.itemId = itemId
        self.summary = summary
        self.details = details
        self.isResolved = isResolved
    }
}
