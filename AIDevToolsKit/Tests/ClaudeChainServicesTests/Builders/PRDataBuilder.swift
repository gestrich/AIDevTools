/**
 * Builder for creating test PR data
 * 
 * Swift port of tests/builders/pr_data_builder.py
 */

import Foundation
import ClaudeChainService

/// Fluent interface for creating test GitHubPullRequest objects
/// 
/// Provides a clean way to create GitHubPullRequest instances for tests
/// with sensible defaults matching real GitHub behavior.
///
/// Example:
///     let pr = PRDataBuilder()
///         .withNumber(123)
///         .withTitle("Task 3 - Add feature")
///         .withState("open")
///         .withHeadRefName("claude-chain-my-project-3")
///         .build()
public class PRDataBuilder {
    private var number: Int = 123
    private var title: String = "Task 1 - Default task"
    private var state: String = "open"
    private var createdAt: Date = Date()
    private var mergedAt: Date?
    private var assignees: [GitHubUser] = []
    private var labels: [String] = ["claudechain"]
    private var headRefName: String? = "claude-chain-sample-project-1"
    private var baseRefName: String? = "main"
    private var url: String? = "https://github.com/owner/repo/pull/123"
    
    public init() {}
    
    /// Set the PR number
    ///
    /// - Parameter number: PR number
    /// - Returns: Self for method chaining
    @discardableResult
    public func withNumber(_ number: Int) -> PRDataBuilder {
        self.number = number
        // Auto-update URL to match
        self.url = "https://github.com/owner/repo/pull/\(number)"
        return self
    }
    
    /// Set the PR title
    ///
    /// - Parameter title: PR title
    /// - Returns: Self for method chaining
    @discardableResult
    public func withTitle(_ title: String) -> PRDataBuilder {
        self.title = title
        return self
    }
    
    /// Set PR data based on task information
    ///
    /// Automatically sets title and branch name based on task.
    ///
    /// - Parameters:
    ///   - taskHash: 8-character hash identifier
    ///   - description: Task description
    ///   - project: Project name (default: "sample-project")
    /// - Returns: Self for method chaining
    @discardableResult
    public func withTask(_ taskHash: String, _ description: String, project: String = "sample-project") -> PRDataBuilder {
        self.title = "ClaudeChain: \(description)"
        self.headRefName = "claude-chain-\(project)-\(taskHash)"
        return self
    }
    
    /// Set the PR state
    ///
    /// - Parameters:
    ///   - state: PR state ("open", "closed", "merged")
    ///   - merged: Whether the PR was merged (only relevant for "closed" state)
    /// - Returns: Self for method chaining
    @discardableResult
    public func withState(_ state: String, merged: Bool = false) -> PRDataBuilder {
        self.state = state
        if state == "closed" && merged {
            self.mergedAt = Date()
        } else if state == "merged" {
            self.mergedAt = Date()
        } else {
            self.mergedAt = nil
        }
        return self
    }
    
    /// Mark PR as closed and merged
    ///
    /// - Returns: Self for method chaining
    @discardableResult
    public func asMerged() -> PRDataBuilder {
        self.state = "merged"
        self.mergedAt = Date()
        return self
    }
    
    /// Mark PR as closed (but not merged)
    ///
    /// - Returns: Self for method chaining
    @discardableResult
    public func asClosed() -> PRDataBuilder {
        self.state = "closed"
        self.mergedAt = nil
        return self
    }
    
    /// Set the PR author
    ///
    /// - Parameter username: GitHub username
    /// - Returns: Self for method chaining
    @discardableResult
    public func withUser(_ username: String) -> PRDataBuilder {
        // Note: We don't store the author directly in GitHubPullRequest,
        // but this is here for API compatibility with Python tests
        return self
    }
    
    /// Set the head branch name
    ///
    /// - Parameter branchName: Branch name
    /// - Returns: Self for method chaining
    @discardableResult
    public func withHeadRefName(_ branchName: String) -> PRDataBuilder {
        self.headRefName = branchName
        return self
    }
    
    /// Set the base branch name
    ///
    /// - Parameter branchName: Base branch name (default: "main")
    /// - Returns: Self for method chaining
    @discardableResult
    public func withBaseRefName(_ branchName: String) -> PRDataBuilder {
        self.baseRefName = branchName
        return self
    }
    
    /// Add a label to the PR
    ///
    /// - Parameter label: Label name
    /// - Returns: Self for method chaining
    @discardableResult
    public func withLabel(_ label: String) -> PRDataBuilder {
        if !labels.contains(label) {
            labels.append(label)
        }
        return self
    }
    
    /// Set PR labels (replaces existing)
    ///
    /// - Parameter labels: Label names
    /// - Returns: Self for method chaining
    @discardableResult
    public func withLabels(_ labels: [String]) -> PRDataBuilder {
        self.labels = labels
        return self
    }
    
    /// Set creation timestamp
    ///
    /// - Parameter timestamp: Creation date
    /// - Returns: Self for method chaining
    @discardableResult
    public func withCreatedAt(_ timestamp: Date) -> PRDataBuilder {
        self.createdAt = timestamp
        return self
    }
    
    /// Set creation timestamp from string
    ///
    /// - Parameter timestamp: ISO 8601 timestamp string
    /// - Returns: Self for method chaining
    @discardableResult
    public func withCreatedAt(_ timestamp: String) -> PRDataBuilder {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: timestamp) {
            self.createdAt = date
        }
        return self
    }
    
    /// Add assignees to the PR
    ///
    /// - Parameter assignees: List of GitHub usernames
    /// - Returns: Self for method chaining
    @discardableResult
    public func withAssignees(_ assignees: [String]) -> PRDataBuilder {
        self.assignees = assignees.map { GitHubUser(login: $0, name: nil, avatarURL: "") }
        return self
    }
    
    /// Build and return the GitHubPullRequest object
    ///
    /// - Returns: Complete GitHubPullRequest ready for use in tests
    public func build() -> GitHubPullRequest {
        return GitHubPullRequest(
            number: number,
            title: title,
            state: state,
            createdAt: createdAt,
            mergedAt: mergedAt,
            assignees: assignees,
            labels: labels,
            headRefName: headRefName,
            baseRefName: baseRefName,
            url: url
        )
    }
    
    // MARK: - Static Helper Methods
    
    /// Quick helper for creating an open PR
    ///
    /// - Parameters:
    ///   - number: PR number (default: 123)
    ///   - taskHash: Task hash for branch name (default: "a1b2c3d4")
    /// - Returns: Open GitHubPullRequest
    public static func openPR(number: Int = 123, taskHash: String = "a1b2c3d4") -> GitHubPullRequest {
        return PRDataBuilder()
            .withNumber(number)
            .withTask(taskHash, "Task \(taskHash)")
            .build()
    }
    
    /// Quick helper for creating a merged PR
    ///
    /// - Parameters:
    ///   - number: PR number (default: 123)
    ///   - taskHash: Task hash for branch name (default: "a1b2c3d4")
    /// - Returns: Merged GitHubPullRequest
    public static func mergedPR(number: Int = 123, taskHash: String = "a1b2c3d4") -> GitHubPullRequest {
        return PRDataBuilder()
            .withNumber(number)
            .withTask(taskHash, "Task \(taskHash)")
            .asMerged()
            .build()
    }
}