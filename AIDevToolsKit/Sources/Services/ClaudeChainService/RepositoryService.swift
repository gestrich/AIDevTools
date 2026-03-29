import Foundation
import GitSDK

/// Service for repository operations that combine Git and GitHub knowledge
public struct RepositoryService: Sendable {
    
    private let gitClient: GitClient
    
    public init(gitClient: GitClient = GitClient()) {
        self.gitClient = gitClient
    }
    
    /// Get the current repository name from git remote
    ///
    /// Determines the GitHub repository name by parsing the git remote origin URL.
    /// Works with both HTTPS and SSH remote URLs.
    ///
    /// This is a service-level concern because it combines:
    /// - GitClient (low-level git operations) 
    /// - GitHub URL parsing logic (domain knowledge)
    ///
    /// - Parameter workingDirectory: Directory to run git commands in (default: current directory)
    /// - Returns: Repository name in "owner/repo" format
    /// - Throws: RepositoryServiceError if unable to determine repository
    ///
    /// Example:
    ///     // Get current repo
    ///     let repo = getCurrentRepository()  // Returns "owner/repo"
    ///     
    ///     // Get repo from specific directory  
    ///     let repo = getCurrentRepository(workingDirectory: "/path/to/repo")
    public func getCurrentRepository(workingDirectory: String) async throws -> String {
        // Get the remote origin URL using GitClient
        let remoteUrl = try await gitClient.remoteGetURL(name: "origin", workingDirectory: workingDirectory)
        
        // Parse the URL to extract owner/repo
        // Handle both SSH (git@github.com:owner/repo.git) and HTTPS (https://github.com/owner/repo.git) formats
        if let repo = extractRepoFromUrl(remoteUrl) {
            return repo
        } else {
            throw RepositoryServiceError("Unable to parse repository name from remote URL: \(remoteUrl)")
        }
    }
    
    /// Helper to extract owner/repo from various Git URL formats
    private func extractRepoFromUrl(_ url: String) -> String? {
        // SSH format: git@github.com:owner/repo.git
        if url.hasPrefix("git@github.com:") {
            let withoutPrefix = String(url.dropFirst("git@github.com:".count))
            let withoutSuffix = withoutPrefix.hasSuffix(".git") ? String(withoutPrefix.dropLast(4)) : withoutPrefix
            return withoutSuffix
        }
        
        // HTTPS format: https://github.com/owner/repo.git
        if url.hasPrefix("https://github.com/") {
            let withoutPrefix = String(url.dropFirst("https://github.com/".count))
            let withoutSuffix = withoutPrefix.hasSuffix(".git") ? String(withoutPrefix.dropLast(4)) : withoutPrefix
            return withoutSuffix
        }
        
        return nil
    }
}

/// Errors for RepositoryService operations
public struct RepositoryServiceError: Error, Sendable, CustomStringConvertible {
    public let description: String
    
    public init(_ description: String) {
        self.description = description
    }
}