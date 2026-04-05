import Foundation

public enum RunSpecChainTaskError: LocalizedError, Sendable {
    case capacityExceeded(project: String, openCount: Int, maxOpen: Int)

    public var errorDescription: String? {
        switch self {
        case .capacityExceeded(let project, let openCount, let maxOpen):
            return "Project '\(project)' is at capacity: \(openCount)/\(maxOpen) async slots in use. Cannot create PR."
        }
    }
}
