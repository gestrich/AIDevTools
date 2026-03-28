/**
 * Test helpers and utility functions for service tests
 * 
 * Provides common utilities used across service test files
 */

import Foundation
import ClaudeChainService
import ClaudeChainServices
import ClaudeChainInfrastructure
import XCTest

/// Protocol for PR service functionality used in tests
protocol PRServiceProtocol {
    func getOpenPrsForProject(project: String, label: String) -> [GitHubPullRequest]
    func getProjectPrs(projectName: String, state: String, label: String) -> [GitHubPullRequest]
}

/// Extension to make PRService conform to the protocol
extension PRService: PRServiceProtocol {}

/// Helper to create a GitHubPullRequest for testing
///
/// Equivalent to Python's create_github_pr helper function
///
/// - Parameters:
///   - prNumber: PR number 
///   - taskHash: 8-character task hash
///   - project: Project name (default: "myproject")
///   - taskDesc: Task description (default: "Task {hash}")
/// - Returns: GitHubPullRequest instance
func createGitHubPR(
    prNumber: Int,
    taskHash: String,
    project: String = "myproject",
    taskDesc: String? = nil
) -> GitHubPullRequest {
    let description = taskDesc ?? "Task \(String(taskHash.prefix(8)))"
    
    return GitHubPullRequest(
        number: prNumber,
        title: "ClaudeChain: \(description)",
        state: "open",
        createdAt: Date(),
        mergedAt: nil,
        assignees: [],
        labels: ["claudechain"],
        headRefName: "claude-chain-\(project)-\(taskHash)",
        baseRefName: "main",
        url: "https://github.com/owner/repo/pull/\(prNumber)"
    )
}

/// Mock PRService for testing
///
/// Provides a simple mock implementation that can be configured
/// with predetermined responses
class MockPRService: PRServiceProtocol {
    private let repo: String
    var mockGetOpenPrsForProjectResult: [GitHubPullRequest] = []
    var mockGetProjectPrsResult: [GitHubPullRequest] = []
    var getOpenPrsForProjectCalls: [(String, String)] = []
    var getProjectPrsCalls: [(String, String, String)] = []
    
    init(repo: String) {
        self.repo = repo
    }
    
    func getOpenPrsForProject(project: String, label: String) -> [GitHubPullRequest] {
        getOpenPrsForProjectCalls.append((project, label))
        return mockGetOpenPrsForProjectResult
    }
    
    func getProjectPrs(projectName: String, state: String, label: String) -> [GitHubPullRequest] {
        getProjectPrsCalls.append((projectName, state, label))
        return mockGetProjectPrsResult
    }
}