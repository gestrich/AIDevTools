/// Test builders for creating test data in ClaudeChain domain tests
///
/// Provides a fluent interface for creating test configuration data,
/// spec file content, and PR data with sensible defaults.
import Foundation
@testable import ClaudeChainService

/// Builder for creating test configuration data
public class ConfigBuilder {
    private var assignee: String?
    private var project: String = "sample-project"
    private var customFields: [String: Any] = [:]
    
    /// Initialize builder with default values
    public init() {}
    
    /// Set the assignee for the configuration
    @discardableResult
    public func withAssignee(_ username: String) -> ConfigBuilder {
        self.assignee = username
        return self
    }
    
    /// Clear the assignee (for testing no assignee)
    @discardableResult
    public func withNoAssignee() -> ConfigBuilder {
        self.assignee = nil
        return self
    }
    
    /// Set the project name
    @discardableResult
    public func withProject(_ projectName: String) -> ConfigBuilder {
        self.project = projectName
        return self
    }
    
    /// Add a custom field to the configuration
    @discardableResult
    public func withField(_ key: String, value: Any) -> ConfigBuilder {
        self.customFields[key] = value
        return self
    }
    
    /// Build and return the configuration dictionary
    public func build() -> [String: Any] {
        var config: [String: Any] = [
            "project": project
        ]
        
        if let assignee = assignee {
            config["assignee"] = assignee
        }
        
        // Merge any custom fields
        for (key, value) in customFields {
            config[key] = value
        }
        
        return config
    }
    
    /// Quick helper for creating a config with an assignee
    public static func withDefaultAssignee(_ username: String = "alice") -> [String: Any] {
        return ConfigBuilder().withAssignee(username).build()
    }
    
    /// Quick helper for creating a default configuration
    public static func defaultConfig() -> [String: Any] {
        return ConfigBuilder().withAssignee("alice").build()
    }
    
    /// Quick helper for creating a configuration with no assignee
    public static func empty() -> [String: Any] {
        return ConfigBuilder().withNoAssignee().build()
    }
}

/// Builder for creating test spec.md file content
public class SpecFileBuilder {
    private var title: String = "Project Specification"
    private var overview: String?
    private var tasks: [(completed: Bool, description: String)] = []
    private var customSections: [String] = []
    
    /// Initialize builder with default values
    public init() {}
    
    /// Set the document title
    @discardableResult
    public func withTitle(_ title: String) -> SpecFileBuilder {
        self.title = title
        return self
    }
    
    /// Add an overview section
    @discardableResult
    public func withOverview(_ overview: String) -> SpecFileBuilder {
        self.overview = overview
        return self
    }
    
    /// Add a task to the spec
    @discardableResult
    public func addTask(_ description: String, completed: Bool = false) -> SpecFileBuilder {
        tasks.append((completed: completed, description: description))
        return self
    }
    
    /// Add a completed task
    @discardableResult
    public func addCompletedTask(_ description: String) -> SpecFileBuilder {
        return addTask(description, completed: true)
    }
    
    /// Add multiple tasks at once
    @discardableResult
    public func addTasks(_ descriptions: [String], completed: Bool = false) -> SpecFileBuilder {
        for description in descriptions {
            addTask(description, completed: completed)
        }
        return self
    }
    
    /// Add a custom markdown section
    @discardableResult
    public func addSection(_ sectionMarkdown: String) -> SpecFileBuilder {
        customSections.append(sectionMarkdown)
        return self
    }
    
    /// Build and return the spec.md content
    public func build() -> String {
        var lines: [String] = []
        
        // Title
        lines.append("# \(title)")
        lines.append("")
        
        // Overview section
        if let overview = overview {
            lines.append("## Overview")
            lines.append(overview)
            lines.append("")
        }
        
        // Tasks section
        if !tasks.isEmpty {
            lines.append("## Tasks")
            lines.append("")
            for task in tasks {
                let checkbox = task.completed ? "[x]" : "[ ]"
                lines.append("- \(checkbox) \(task.description)")
            }
            lines.append("")
        }
        
        // Custom sections
        for section in customSections {
            lines.append(section)
            if !section.hasSuffix("\n") {
                lines.append("")
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Build and write the spec.md content to a file
    @discardableResult
    public func writeTo(_ url: URL) -> URL {
        let fileURL = url.hasDirectoryPath ? url.appendingPathComponent("spec.md") : url
        try! build().write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
    
    /// Quick helper for an empty spec with no tasks
    public static func empty() -> String {
        return SpecFileBuilder()
            .withOverview("This project has no tasks yet.")
            .build()
    }
    
    /// Quick helper for a spec with all tasks completed
    public static func allCompleted(numTasks: Int = 3) -> String {
        let builder = SpecFileBuilder()
        for i in 1...numTasks {
            builder.addCompletedTask("Task \(i)")
        }
        return builder.build()
    }
    
    /// Quick helper for a spec with mixed task states
    public static func mixedProgress(completed: Int = 2, pending: Int = 3) -> String {
        let builder = SpecFileBuilder()
        
        // Add completed tasks
        for i in 1...completed {
            builder.addCompletedTask("Task \(i)")
        }
        
        // Add pending tasks
        for i in (completed + 1)...(completed + pending) {
            builder.addTask("Task \(i)")
        }
        
        return builder.build()
    }
    
    /// Quick helper for a default spec (matching conftest.py fixture)
    public static func defaultSpec() -> String {
        return SpecFileBuilder.mixedProgress(completed: 2, pending: 3)
    }
}

/// Builder for creating test PR data
public class PRDataBuilder {
    private var number: Int = 123
    private var title: String = "Task 1 - Default task"
    private var state: String = "open"
    private var merged: Bool = false
    private var htmlURL: String = "https://github.com/owner/repo/pull/123"
    private var userLogin: String = "alice"
    private var createdAt: String = "2025-01-15T10:00:00Z"
    private var updatedAt: String = "2025-01-15T10:00:00Z"
    private var headRef: String = "claude-chain-sample-project-1"
    private var baseRef: String = "main"
    private var labels: [[String: String]] = [["name": "claude-chain"]]
    private var customFields: [String: Any] = [:]
    
    /// Initialize builder with default values
    public init() {}
    
    /// Set the PR number
    @discardableResult
    public func withNumber(_ number: Int) -> PRDataBuilder {
        self.number = number
        self.htmlURL = "https://github.com/owner/repo/pull/\(number)"
        return self
    }
    
    /// Set the PR title
    @discardableResult
    public func withTitle(_ title: String) -> PRDataBuilder {
        self.title = title
        return self
    }
    
    /// Set PR data based on task information
    @discardableResult
    public func withTask(_ taskIndex: Int, _ description: String, _ project: String = "sample-project") -> PRDataBuilder {
        self.title = "Task \(taskIndex) - \(description)"
        self.headRef = "claude-chain-\(project)-\(taskIndex)"
        return self
    }
    
    /// Set the PR state
    @discardableResult
    public func withState(_ state: String, merged: Bool = false) -> PRDataBuilder {
        self.state = state
        self.merged = (state == "closed") ? merged : false
        return self
    }
    
    /// Mark PR as closed and merged
    @discardableResult
    public func asMerged() -> PRDataBuilder {
        self.state = "closed"
        self.merged = true
        return self
    }
    
    /// Mark PR as closed (but not merged)
    @discardableResult
    public func asClosed() -> PRDataBuilder {
        self.state = "closed"
        self.merged = false
        return self
    }
    
    /// Set the PR author
    @discardableResult
    public func withUser(_ username: String) -> PRDataBuilder {
        self.userLogin = username
        return self
    }
    
    /// Set the head branch name
    @discardableResult
    public func withBranch(_ branchName: String) -> PRDataBuilder {
        self.headRef = branchName
        return self
    }
    
    /// Set the base branch name
    @discardableResult
    public func withBaseBranch(_ branchName: String) -> PRDataBuilder {
        self.baseRef = branchName
        return self
    }
    
    /// Add a label to the PR
    @discardableResult
    public func withLabel(_ label: String) -> PRDataBuilder {
        if !labels.contains(where: { $0["name"] == label }) {
            labels.append(["name": label])
        }
        return self
    }
    
    /// Set PR labels (replaces existing)
    @discardableResult
    public func withLabels(_ labelNames: [String]) -> PRDataBuilder {
        self.labels = labelNames.map { ["name": $0] }
        return self
    }
    
    /// Set creation timestamp
    @discardableResult
    public func withCreatedAt(_ timestamp: String) -> PRDataBuilder {
        self.createdAt = timestamp
        return self
    }
    
    /// Add a custom field to the PR data
    @discardableResult
    public func withField(_ key: String, value: Any) -> PRDataBuilder {
        self.customFields[key] = value
        return self
    }
    
    /// Build and return the PR data dictionary
    public func build() -> [String: Any] {
        var prData: [String: Any] = [
            "number": number,
            "title": title,
            "state": state,
            "html_url": htmlURL,
            "user": ["login": userLogin],
            "created_at": createdAt,
            "updated_at": updatedAt,
            "head": ["ref": headRef],
            "base": ["ref": baseRef],
            "labels": labels
        ]
        
        // Add merged field if closed
        if state == "closed" {
            prData["merged"] = merged
        }
        
        // Merge any custom fields
        for (key, value) in customFields {
            prData[key] = value
        }
        
        return prData
    }
    
    /// Quick helper for creating an open PR
    public static func openPR(number: Int = 123, taskIndex: Int = 1) -> [String: Any] {
        return PRDataBuilder()
            .withNumber(number)
            .withTask(taskIndex, "Task \(taskIndex)")
            .build()
    }
    
    /// Quick helper for creating a merged PR
    public static func mergedPR(number: Int = 123, taskIndex: Int = 1) -> [String: Any] {
        return PRDataBuilder()
            .withNumber(number)
            .withTask(taskIndex, "Task \(taskIndex)")
            .asMerged()
            .build()
    }
}