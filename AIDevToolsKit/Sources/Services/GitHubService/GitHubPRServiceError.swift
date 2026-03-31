import Foundation

public enum GitHubPRServiceError: Error, LocalizedError {
    case missingHeadRefOid(prNumber: Int)

    public var errorDescription: String? {
        switch self {
        case .missingHeadRefOid(let prNumber):
            return "PR #\(prNumber) has no head commit SHA (headRefOid); cannot fetch check runs"
        }
    }
}
