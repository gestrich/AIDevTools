import ClaudeChainService
import Foundation

/// Protocol for GitHubOperations to enable dependency injection in tests
public protocol GitHubOperationsProtocol {
    /// Fetch file content from a specific branch via GitHub API
    ///
    /// - Parameter repo: GitHub repository in format "owner/repo"
    /// - Parameter branch: Branch name to fetch from
    /// - Parameter filePath: Path to file within repository
    /// - Returns: File content as string, or nil if file not found
    /// - Throws: GitHubAPIError if API call fails for reasons other than file not found
    func getFileFromBranch(repo: String, branch: String, filePath: String) throws -> String?
}