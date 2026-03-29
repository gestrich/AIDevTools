import Foundation

public protocol PipelineStep: Sendable {
    var id: String { get }
    var description: String { get }
    var isCompleted: Bool { get }
}

public struct CodeChangeStep: PipelineStep {
    public let id: String
    public let description: String
    public let isCompleted: Bool
    public let prompt: String
    public let skills: [String]
    public let context: [String: String]

    public init(
        id: String,
        description: String,
        isCompleted: Bool = false,
        prompt: String,
        skills: [String] = [],
        context: [String: String] = [:]
    ) {
        self.id = id
        self.description = description
        self.isCompleted = isCompleted
        self.prompt = prompt
        self.skills = skills
        self.context = context
    }
}

public struct ReviewStep: PipelineStep {
    public let id: String
    public let description: String
    public let isCompleted: Bool
    public let scope: ReviewScope
    public let prompt: String
    public let reviewedStepIDs: [String]

    public init(
        id: String,
        description: String,
        isCompleted: Bool = false,
        scope: ReviewScope,
        prompt: String,
        reviewedStepIDs: [String] = []
    ) {
        self.id = id
        self.description = description
        self.isCompleted = isCompleted
        self.scope = scope
        self.prompt = prompt
        self.reviewedStepIDs = reviewedStepIDs
    }
}

public enum ReviewScope: Sendable {
    case allSinceLastReview
    case lastN(Int)
    case stepIDs([String])
}

public struct CreatePRStep: PipelineStep {
    public let id: String
    public let description: String
    public let isCompleted: Bool
    public let titleTemplate: String
    public let bodyTemplate: String
    public let label: String?

    public init(
        id: String,
        description: String,
        isCompleted: Bool = false,
        titleTemplate: String,
        bodyTemplate: String,
        label: String? = nil
    ) {
        self.id = id
        self.description = description
        self.isCompleted = isCompleted
        self.titleTemplate = titleTemplate
        self.bodyTemplate = bodyTemplate
        self.label = label
    }
}
