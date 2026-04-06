import Foundation

public struct ChainExecutionPhase: Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public var status: ChainPhaseStatus

    public init(id: String, displayName: String, status: ChainPhaseStatus = .pending) {
        self.id = id
        self.displayName = displayName
        self.status = status
    }
}

public enum ChainPhaseStatus: Sendable {
    case completed, failed, pending, running, skipped
}
