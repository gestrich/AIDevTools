import Foundation

public struct PhaseStatus: Codable, Sendable {
    public let description: String
    public let status: String

    public var isCompleted: Bool { status == "completed" }

    public init(description: String, status: String) {
        self.description = description
        self.status = status
    }
}

public struct PhaseStatusResponse: Codable, Sendable {
    public let phases: [PhaseStatus]
    public let nextPhaseIndex: Int

    public init(phases: [PhaseStatus], nextPhaseIndex: Int) {
        self.phases = phases
        self.nextPhaseIndex = nextPhaseIndex
    }
}
