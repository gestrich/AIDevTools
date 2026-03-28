import ClaudeChainService
import Foundation

/// Test builders for creating test data with fluent interfaces
/// Swift port of Python test builders

/// Builder for creating test configuration data
public struct ConfigBuilder {
    private var assignee: String? = nil
    private var project: String = "sample-project"
    private var customFields: [String: Any] = [:]
    
    public init() {}
    
    /// Set the assignee for the configuration
    public func withAssignee(_ username: String) -> ConfigBuilder {
        var builder = self
        builder.assignee = username
        return builder
    }
    
    /// Clear the assignee (for testing no assignee)
    public func withNoAssignee() -> ConfigBuilder {
        var builder = self
        builder.assignee = nil
        return builder
    }
    
    /// Set the project name
    public func withProject(_ projectName: String) -> ConfigBuilder {
        var builder = self
        builder.project = projectName
        return builder
    }
    
    /// Add a custom field to the configuration
    public func withField(_ key: String, value: Any) -> ConfigBuilder {
        var builder = self
        builder.customFields[key] = value
        return builder
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
    
    // MARK: - Static Helpers
    
    /// Quick helper for creating a config with an assignee
    public static func withDefaultAssignee(_ username: String = "alice") -> [String: Any] {
        return ConfigBuilder().withAssignee(username).build()
    }
    
    /// Quick helper for creating a default configuration
    public static func `default`() -> [String: Any] {
        return ConfigBuilder().withAssignee("alice").build()
    }
    
    /// Quick helper for creating a configuration with no assignee
    public static func empty() -> [String: Any] {
        return ConfigBuilder().withNoAssignee().build()
    }
}

/// Builder for creating sample PR data structures
public struct PRDataBuilder {
    private var number: Int = 123
    private var title: String = "Sample PR"
    private var state: String = "open"
    private var merged: Bool = false
    private var username: String = "alice"
    private var createdAt: String = "2025-01-15T10:00:00Z"
    private var headRef: String = "feature-branch"
    private var labels: [String] = ["claude-chain"]
    
    public init() {}
    
    public func withNumber(_ number: Int) -> PRDataBuilder {
        var builder = self
        builder.number = number
        return builder
    }
    
    public func withTask(_ taskIndex: Int, _ description: String, _ project: String) -> PRDataBuilder {
        var builder = self
        builder.title = "Task \(taskIndex) - \(description)"
        builder.headRef = "claude-chain-\(project)-\(taskIndex)"
        return builder
    }
    
    public func withUser(_ username: String) -> PRDataBuilder {
        var builder = self
        builder.username = username
        return builder
    }
    
    public func withCreatedAt(_ timestamp: String) -> PRDataBuilder {
        var builder = self
        builder.createdAt = timestamp
        return builder
    }
    
    public func build() -> [String: Any] {
        return [
            "number": number,
            "title": title,
            "state": state,
            "merged": merged,
            "user": ["login": username],
            "created_at": createdAt,
            "head": ["ref": headRef],
            "labels": labels.map { ["name": $0] }
        ]
    }
}

/// Builder for creating spec file content
public struct SpecFileBuilder {
    private var title: String = "Project Specification"
    private var overview: String = "Project overview"
    private var sections: [String] = []
    private var tasks: [String] = []
    
    public init() {}
    
    public func withTitle(_ title: String) -> SpecFileBuilder {
        var builder = self
        builder.title = title
        return builder
    }
    
    public func withOverview(_ overview: String) -> SpecFileBuilder {
        var builder = self
        builder.overview = overview
        return builder
    }
    
    public func addSection(_ section: String) -> SpecFileBuilder {
        var builder = self
        builder.sections.append(section)
        return builder
    }
    
    public func addTask(_ description: String) -> SpecFileBuilder {
        var builder = self
        builder.tasks.append("- [ ] \(description)")
        return builder
    }
    
    public func addCompletedTask(_ description: String) -> SpecFileBuilder {
        var builder = self
        builder.tasks.append("- [x] \(description)")
        return builder
    }
    
    public func build() -> String {
        var content = "# \(title)\n\n\(overview)\n\n"
        
        for section in sections {
            content += "\(section)\n\n"
        }
        
        for task in tasks {
            content += "\(task)\n"
        }
        
        return content
    }
    
    public func writeTo(_ directory: URL) -> URL {
        let specFile = directory.appendingPathComponent("spec.md")
        let content = build()
        
        try! content.write(to: specFile, atomically: true, encoding: .utf8)
        
        return specFile
    }
}

/// Helper for creating artifact data
public struct ArtifactBuilder {
    private var taskIndex: Int = 3
    private var taskDescription: String = "Implement feature X"
    private var project: String = "my-project"
    private var reviewer: String = "alice"
    private var branch: String? = nil
    private var createdAt: String = "2025-01-15T10:00:00Z"
    
    public init() {}
    
    public func withTaskIndex(_ index: Int) -> ArtifactBuilder {
        var builder = self
        builder.taskIndex = index
        return builder
    }
    
    public func withTaskDescription(_ description: String) -> ArtifactBuilder {
        var builder = self
        builder.taskDescription = description
        return builder
    }
    
    public func withProject(_ project: String) -> ArtifactBuilder {
        var builder = self
        builder.project = project
        return builder
    }
    
    public func withReviewer(_ reviewer: String) -> ArtifactBuilder {
        var builder = self
        builder.reviewer = reviewer
        return builder
    }
    
    public func withBranch(_ branch: String) -> ArtifactBuilder {
        var builder = self
        builder.branch = branch
        return builder
    }
    
    public func build() -> [String: Any] {
        let finalBranch = branch ?? "claude-chain-\(project)-\(taskIndex)"
        
        return [
            "task_index": taskIndex,
            "task_description": taskDescription,
            "project": project,
            "reviewer": reviewer,
            "branch": finalBranch,
            "created_at": createdAt
        ]
    }
}