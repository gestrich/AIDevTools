public enum PipelineError: Error, LocalizedError, Sendable {
    case cancelled
    case capacityExceeded(openCount: Int, maxOpen: Int)
    case missingContextValue(key: String)
    case outputTypeMismatch(expected: String, received: String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Pipeline was cancelled"
        case .capacityExceeded(let openCount, let maxOpen):
            return "Pipeline capacity exceeded (\(openCount)/\(maxOpen) open)"
        case .missingContextValue(let key):
            return "Missing context value for key '\(key)'"
        case .outputTypeMismatch(let expected, let received):
            return "Output type mismatch: expected '\(expected)', received '\(received)'"
        }
    }
}
