/**
 * Builders for creating test artifact and metadata data
 * 
 * Swift port of tests/builders/artifact_builder.py
 */

import Foundation
import ClaudeChainService
import ClaudeChainServices

// MARK: - Test-specific Models (matching Python test builders)

/// Test version of TaskMetadata for builder pattern
public struct TestTaskMetadata {
    public let taskIndex: Int
    public let taskDescription: String
    public let project: String
    public let branchName: String
    public let assignee: String
    public let createdAt: Date
    public let workflowRunId: Int
    public let prNumber: Int
    public let mainTaskCostUSD: Double
    public let prSummaryCostUSD: Double
    public let totalCostUSD: Double
    
    public init(
        taskIndex: Int,
        taskDescription: String,
        project: String,
        branchName: String,
        assignee: String,
        createdAt: Date,
        workflowRunId: Int,
        prNumber: Int,
        mainTaskCostUSD: Double = 0.0,
        prSummaryCostUSD: Double = 0.0,
        totalCostUSD: Double = 0.0
    ) {
        self.taskIndex = taskIndex
        self.taskDescription = taskDescription
        self.project = project
        self.branchName = branchName
        self.assignee = assignee
        self.createdAt = createdAt
        self.workflowRunId = workflowRunId
        self.prNumber = prNumber
        self.mainTaskCostUSD = mainTaskCostUSD
        self.prSummaryCostUSD = prSummaryCostUSD
        self.totalCostUSD = totalCostUSD
    }
}

/// Test version of ProjectArtifact for builder pattern  
public struct TestProjectArtifact {
    public let artifactId: Int
    public let artifactName: String
    public let workflowRunId: Int
    public let metadata: TestTaskMetadata?
    
    public init(artifactId: Int, artifactName: String, workflowRunId: Int, metadata: TestTaskMetadata? = nil) {
        self.artifactId = artifactId
        self.artifactName = artifactName
        self.workflowRunId = workflowRunId
        self.metadata = metadata
    }
    
    /// Convenience accessor for task index
    public var taskIndex: Int? {
        if let metadata = metadata {
            return metadata.taskIndex
        }
        // Fallback: parse from name
        let pattern = #"-(\d+)\.json$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(artifactName.startIndex..<artifactName.endIndex, in: artifactName)
        if let match = regex?.firstMatch(in: artifactName, options: [], range: range),
           let matchRange = Range(match.range(at: 1), in: artifactName) {
            return Int(String(artifactName[matchRange]))
        }
        return nil
    }
}

/// Fluent interface for creating TestTaskMetadata objects
///
/// Example:
///     let metadata = TaskMetadataBuilder()
///         .withTask(3, "Implement feature")
///         .withProject("my-project")
///         .withAssignee("alice")
///         .build()
public class TaskMetadataBuilder {
    private var taskIndex: Int = 1
    private var taskDescription: String = "Default task"
    private var project: String = "sample-project"
    private var branchName: String = "claude-chain-sample-project-1"
    private var assignee: String = "alice"
    private var createdAt: Date = {
        let calendar = Calendar.current
        let components = DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2025, month: 1, day: 15, hour: 10, minute: 0, second: 0
        )
        return calendar.date(from: components) ?? Date()
    }()
    private var workflowRunId: Int = 123456789
    private var prNumber: Int = 100
    private var mainTaskCostUSD: Double = 0.0
    private var prSummaryCostUSD: Double = 0.0
    private var totalCostUSD: Double = 0.0
    
    public init() {}
    
    /// Set task index and description
    ///
    /// Automatically updates branch name to match.
    ///
    /// - Parameters:
    ///   - index: Task index (1-based)
    ///   - description: Task description
    /// - Returns: Self for method chaining
    @discardableResult
    public func withTask(_ index: Int, _ description: String) -> TaskMetadataBuilder {
        self.taskIndex = index
        self.taskDescription = description
        self.branchName = "claude-chain-\(self.project)-\(index)"
        return self
    }
    
    /// Set project name
    ///
    /// Automatically updates branch name to match.
    ///
    /// - Parameter project: Project name
    /// - Returns: Self for method chaining
    @discardableResult
    public func withProject(_ project: String) -> TaskMetadataBuilder {
        self.project = project
        self.branchName = "claude-chain-\(project)-\(self.taskIndex)"
        return self
    }
    
    /// Set assignee username
    ///
    /// - Parameter assignee: Assignee username
    /// - Returns: Self for method chaining
    @discardableResult
    public func withAssignee(_ assignee: String) -> TaskMetadataBuilder {
        self.assignee = assignee
        return self
    }
    
    /// Set branch name (overrides auto-generated name)
    ///
    /// - Parameter branchName: Custom branch name
    /// - Returns: Self for method chaining
    @discardableResult
    public func withBranchName(_ branchName: String) -> TaskMetadataBuilder {
        self.branchName = branchName
        return self
    }
    
    /// Set PR number
    ///
    /// - Parameter prNumber: PR number
    /// - Returns: Self for method chaining
    @discardableResult
    public func withPRNumber(_ prNumber: Int) -> TaskMetadataBuilder {
        self.prNumber = prNumber
        return self
    }
    
    /// Set workflow run ID
    ///
    /// - Parameter runId: GitHub Actions workflow run ID
    /// - Returns: Self for method chaining
    @discardableResult
    public func withWorkflowRunId(_ runId: Int) -> TaskMetadataBuilder {
        self.workflowRunId = runId
        return self
    }
    
    /// Set cost information
    ///
    /// - Parameters:
    ///   - mainTask: Main task cost in USD
    ///   - prSummary: PR summary cost in USD
    /// - Returns: Self for method chaining
    @discardableResult
    public func withCosts(mainTask: Double = 0.0, prSummary: Double = 0.0) -> TaskMetadataBuilder {
        self.mainTaskCostUSD = mainTask
        self.prSummaryCostUSD = prSummary
        self.totalCostUSD = mainTask + prSummary
        return self
    }
    
    /// Set creation timestamp
    ///
    /// - Parameter createdAt: Creation datetime
    /// - Returns: Self for method chaining
    @discardableResult
    public func withCreatedAt(_ createdAt: Date) -> TaskMetadataBuilder {
        self.createdAt = createdAt
        return self
    }
    
    /// Build and return the TestTaskMetadata object
    ///
    /// - Returns: Complete TestTaskMetadata object
    public func build() -> TestTaskMetadata {
        return TestTaskMetadata(
            taskIndex: taskIndex,
            taskDescription: taskDescription,
            project: project,
            branchName: branchName,
            assignee: assignee,
            createdAt: createdAt,
            workflowRunId: workflowRunId,
            prNumber: prNumber,
            mainTaskCostUSD: mainTaskCostUSD,
            prSummaryCostUSD: prSummaryCostUSD,
            totalCostUSD: totalCostUSD
        )
    }
}

/// Fluent interface for creating TestProjectArtifact objects
///
/// Example:
///     let artifact = ArtifactBuilder()
///         .withId(123)
///         .withTask(3, "Implement feature", "my-project")
///         .withMetadata()
///         .build()
public class ArtifactBuilder {
    private var artifactId: Int = 12345
    private var artifactName: String = "task-metadata-sample-project-1.json"
    private var workflowRunId: Int = 123456789
    private var metadata: TestTaskMetadata?
    private var metadataBuilder: TaskMetadataBuilder?
    
    public init() {}
    
    /// Set artifact ID
    ///
    /// - Parameter artifactId: Artifact ID
    /// - Returns: Self for method chaining
    @discardableResult
    public func withId(_ artifactId: Int) -> ArtifactBuilder {
        self.artifactId = artifactId
        return self
    }
    
    /// Set artifact name
    ///
    /// - Parameter name: Artifact name (e.g., "task-metadata-project-3.json")
    /// - Returns: Self for method chaining
    @discardableResult
    public func withName(_ name: String) -> ArtifactBuilder {
        self.artifactName = name
        return self
    }
    
    /// Set artifact name based on task information
    ///
    /// - Parameters:
    ///   - taskIndex: Task index (1-based)
    ///   - description: Task description (optional, only affects metadata)
    ///   - project: Project name
    /// - Returns: Self for method chaining
    @discardableResult
    public func withTask(_ taskIndex: Int, _ description: String? = nil, project: String = "sample-project") -> ArtifactBuilder {
        self.artifactName = "task-metadata-\(project)-\(taskIndex).json"
        
        // Also prepare metadata builder if we'll create metadata
        if self.metadataBuilder == nil {
            self.metadataBuilder = TaskMetadataBuilder()
        }
        
        self.metadataBuilder = self.metadataBuilder?
            .withTask(taskIndex, description ?? "Task \(taskIndex)")
            .withProject(project)
        
        return self
    }
    
    /// Set workflow run ID
    ///
    /// - Parameter runId: GitHub Actions workflow run ID
    /// - Returns: Self for method chaining
    @discardableResult
    public func withWorkflowRunId(_ runId: Int) -> ArtifactBuilder {
        self.workflowRunId = runId
        return self
    }
    
    /// Add metadata to the artifact
    ///
    /// If metadata is None, builds metadata from the current metadata builder state.
    ///
    /// - Parameter metadata: TestTaskMetadata object (or nil to auto-build)
    /// - Returns: Self for method chaining
    @discardableResult
    public func withMetadata(_ metadata: TestTaskMetadata? = nil) -> ArtifactBuilder {
        if let metadata = metadata {
            self.metadata = metadata
        } else {
            // Build from metadata builder if available
            if let metadataBuilder = self.metadataBuilder {
                // Make sure workflow_run_id matches
                self.metadata = metadataBuilder
                    .withWorkflowRunId(self.workflowRunId)
                    .build()
            }
        }
        
        return self
    }
    
    /// Build and return the TestProjectArtifact object
    ///
    /// - Returns: Complete TestProjectArtifact object
    public func build() -> TestProjectArtifact {
        return TestProjectArtifact(
            artifactId: artifactId,
            artifactName: artifactName,
            workflowRunId: workflowRunId,
            metadata: metadata
        )
    }
    
    // MARK: - Static Helper Methods
    
    /// Quick helper for creating a simple artifact without metadata
    ///
    /// - Parameters:
    ///   - artifactId: Artifact ID
    ///   - taskIndex: Task index for naming
    /// - Returns: TestProjectArtifact without metadata
    public static func simple(artifactId: Int = 12345, taskIndex: Int = 1) -> TestProjectArtifact {
        return ArtifactBuilder()
            .withId(artifactId)
            .withTask(taskIndex)
            .build()
    }
    
    /// Quick helper for creating an artifact with complete metadata
    ///
    /// - Parameters:
    ///   - artifactId: Artifact ID
    ///   - taskIndex: Task index
    ///   - project: Project name
    /// - Returns: TestProjectArtifact with full metadata
    public static func withFullMetadata(
        artifactId: Int = 12345,
        taskIndex: Int = 1,
        project: String = "sample-project"
    ) -> TestProjectArtifact {
        return ArtifactBuilder()
            .withId(artifactId)
            .withTask(taskIndex, "Task \(taskIndex)", project: project)
            .withMetadata()
            .build()
    }
}

// MARK: - Type Aliases for Compatibility

/// Type alias to match Python test naming
public typealias ArtifactTaskMetadataBuilder = TaskMetadataBuilder