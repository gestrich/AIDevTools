/**
 * Builder for creating test configuration data
 * 
 * Swift port of tests/builders/config_builder.py
 */

import Foundation
import ClaudeChainService

/// Fluent interface for creating test configuration data
/// 
/// Provides a clean, readable way to create ProjectConfiguration objects for tests
/// with sensible defaults.
///
/// Example:
///     let config = ConfigBuilder()
///         .withAssignee("alice")
///         .withProject("my-project")
///         .build()
public class ConfigBuilder {
    private var assignees: [String] = []
    private var reviewers: [String] = []
    private var project: Project = Project(name: "sample-project")
    private var maxOpenPRs: Int?
    private var baseBranch: String?
    private var allowedTools: String?
    private var stalePRDays: Int?
    private var labels: String?
    
    public init() {}
    
    /// Set a single assignee for the configuration
    ///
    /// - Parameter username: GitHub username of the assignee
    /// - Returns: Self for method chaining
    @discardableResult
    public func withAssignee(_ username: String) -> ConfigBuilder {
        self.assignees = [username]
        return self
    }
    
    /// Set multiple assignees for the configuration
    ///
    /// - Parameter assignees: List of GitHub usernames
    /// - Returns: Self for method chaining
    @discardableResult
    public func withAssignees(_ assignees: [String]) -> ConfigBuilder {
        self.assignees = assignees
        return self
    }
    
    /// Clear all assignees (for testing no assignee)
    ///
    /// - Returns: Self for method chaining
    @discardableResult
    public func withNoAssignee() -> ConfigBuilder {
        self.assignees = []
        return self
    }
    
    /// Set multiple reviewers for the configuration
    ///
    /// - Parameter reviewers: List of GitHub usernames
    /// - Returns: Self for method chaining
    @discardableResult
    public func withReviewers(_ reviewers: [String]) -> ConfigBuilder {
        self.reviewers = reviewers
        return self
    }
    
    /// Set the project for the configuration
    ///
    /// - Parameter projectName: Name of the project
    /// - Returns: Self for method chaining
    @discardableResult
    public func withProject(_ projectName: String) -> ConfigBuilder {
        self.project = Project(name: projectName)
        return self
    }
    
    /// Set the maximum number of open PRs
    ///
    /// - Parameter maxOpenPRs: Maximum number of open PRs
    /// - Returns: Self for method chaining
    @discardableResult
    public func withMaxOpenPRs(_ maxOpenPRs: Int) -> ConfigBuilder {
        self.maxOpenPRs = maxOpenPRs
        return self
    }
    
    /// Build and return the ProjectConfiguration object
    ///
    /// - Returns: Complete ProjectConfiguration ready for use in tests
    public func build() -> ProjectConfiguration {
        return ProjectConfiguration(
            project: project,
            baseBranch: baseBranch,
            allowedTools: allowedTools,
            stalePRDays: stalePRDays,
            labels: labels,
            maxOpenPRs: maxOpenPRs,
            assignees: assignees,
            reviewers: reviewers
        )
    }
    
    // MARK: - Static Helper Methods
    
    /// Quick helper for creating a config with a default assignee
    ///
    /// - Parameter username: GitHub username (default: "alice")
    /// - Returns: ProjectConfiguration with assignee
    public static func withDefaultAssignee(_ username: String = "alice") -> ProjectConfiguration {
        return ConfigBuilder().withAssignee(username).build()
    }
    
    /// Quick helper for creating a default configuration
    ///
    /// Creates a configuration with assignee alice.
    ///
    /// - Returns: Default ProjectConfiguration
    public static func defaultConfig() -> ProjectConfiguration {
        return ConfigBuilder().withAssignee("alice").build()
    }
    
    /// Quick helper for creating a config with a single reviewer
    ///
    /// - Returns: ProjectConfiguration with single reviewer
    public static func singleReviewer() -> ProjectConfiguration {
        return ConfigBuilder().withReviewers(["charlie"]).build()
    }
    
    /// Quick helper for creating a configuration with no assignees
    ///
    /// - Returns: ProjectConfiguration without assignees
    public static func empty() -> ProjectConfiguration {
        return ConfigBuilder().withNoAssignee().build()
    }
}