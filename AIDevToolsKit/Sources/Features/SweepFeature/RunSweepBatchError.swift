import Foundation

public enum RunSweepBatchError: LocalizedError {
    case openPRExists(count: Int, branchPrefix: String)
    case openPRQueryFailed(branchPrefix: String)

    public var errorDescription: String? {
        switch self {
        case .openPRExists(let count, let prefix):
            return "\(count) open PR(s) already exist with prefix '\(prefix)'. Merge or close them before starting a new batch."
        case .openPRQueryFailed(let prefix):
            return "Failed to query open PRs for prefix '\(prefix)'. Check gh authentication."
        }
    }
}
