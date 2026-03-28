/**
 * Tests for ArtifactBuilder and TaskMetadataBuilder
 * 
 * Verifies that the Swift ports work correctly and produce expected output.
 */

import XCTest
@testable import ClaudeChainService
@testable import ClaudeChainServices

final class ArtifactBuilderTests: XCTestCase {
    
    func testTaskMetadataBuilderDefault() throws {
        // Test basic builder with defaults
        let metadata = TaskMetadataBuilder().build()
        
        XCTAssertEqual(metadata.taskIndex, 1)
        XCTAssertEqual(metadata.taskDescription, "Default task")
        XCTAssertEqual(metadata.project, "sample-project")
        XCTAssertEqual(metadata.branchName, "claude-chain-sample-project-1")
        XCTAssertEqual(metadata.assignee, "alice")
        XCTAssertEqual(metadata.workflowRunId, 123456789)
        XCTAssertEqual(metadata.prNumber, 100)
        XCTAssertEqual(metadata.mainTaskCostUSD, 0.0)
        XCTAssertEqual(metadata.prSummaryCostUSD, 0.0)
        XCTAssertEqual(metadata.totalCostUSD, 0.0)
    }
    
    func testTaskMetadataBuilderWithTask() throws {
        // Test fluent interface with task information
        let metadata = TaskMetadataBuilder()
            .withTask(3, "Implement feature")
            .withProject("my-project")
            .withAssignee("bob")
            .build()
        
        XCTAssertEqual(metadata.taskIndex, 3)
        XCTAssertEqual(metadata.taskDescription, "Implement feature")
        XCTAssertEqual(metadata.project, "my-project")
        XCTAssertEqual(metadata.branchName, "claude-chain-my-project-3")
        XCTAssertEqual(metadata.assignee, "bob")
    }
    
    func testTaskMetadataBuilderWithCosts() throws {
        // Test cost handling
        let metadata = TaskMetadataBuilder()
            .withCosts(mainTask: 1.50, prSummary: 0.25)
            .build()
        
        XCTAssertEqual(metadata.mainTaskCostUSD, 1.50, accuracy: 0.001)
        XCTAssertEqual(metadata.prSummaryCostUSD, 0.25, accuracy: 0.001)
        XCTAssertEqual(metadata.totalCostUSD, 1.75, accuracy: 0.001)
    }
    
    func testTaskMetadataBuilderBranchNameUpdate() throws {
        // Test that branch name updates when project or task changes
        let metadata = TaskMetadataBuilder()
            .withProject("initial-project")  // Sets branch to claude-chain-initial-project-1
            .withTask(5, "New task")         // Updates branch to claude-chain-initial-project-5
            .withProject("final-project")    // Updates branch to claude-chain-final-project-5
            .build()
        
        XCTAssertEqual(metadata.branchName, "claude-chain-final-project-5")
        XCTAssertEqual(metadata.taskIndex, 5)
        XCTAssertEqual(metadata.project, "final-project")
    }
    
    func testTaskMetadataBuilderCustomBranchName() throws {
        // Test custom branch name override
        let metadata = TaskMetadataBuilder()
            .withTask(2, "Feature X")
            .withBranchName("custom-branch-name")
            .build()
        
        XCTAssertEqual(metadata.branchName, "custom-branch-name")
        XCTAssertEqual(metadata.taskIndex, 2)
    }
    
    func testArtifactBuilderDefault() throws {
        // Test basic artifact builder
        let artifact = ArtifactBuilder().build()
        
        XCTAssertEqual(artifact.artifactId, 12345)
        XCTAssertEqual(artifact.artifactName, "task-metadata-sample-project-1.json")
        XCTAssertEqual(artifact.workflowRunId, 123456789)
        XCTAssertNil(artifact.metadata)
    }
    
    func testArtifactBuilderWithTask() throws {
        // Test artifact name generation from task info
        let artifact = ArtifactBuilder()
            .withTask(3, "Some task", project: "my-project")
            .build()
        
        XCTAssertEqual(artifact.artifactName, "task-metadata-my-project-3.json")
        XCTAssertNil(artifact.metadata)  // metadata not built unless requested
    }
    
    func testArtifactBuilderWithMetadata() throws {
        // Test artifact with auto-generated metadata
        let artifact = ArtifactBuilder()
            .withTask(2, "Test task", project: "test-project")
            .withWorkflowRunId(999888777)
            .withMetadata()
            .build()
        
        XCTAssertEqual(artifact.artifactName, "task-metadata-test-project-2.json")
        XCTAssertEqual(artifact.workflowRunId, 999888777)
        
        // Check that metadata was generated
        XCTAssertNotNil(artifact.metadata)
        let metadata = artifact.metadata!
        XCTAssertEqual(metadata.taskIndex, 2)
        XCTAssertEqual(metadata.taskDescription, "Test task")
        XCTAssertEqual(metadata.project, "test-project")
        XCTAssertEqual(metadata.workflowRunId, 999888777)
    }
    
    func testArtifactBuilderTaskIndexParsing() throws {
        // Test that task index can be parsed from artifact name
        let artifact = ArtifactBuilder()
            .withName("task-metadata-project-name-42.json")
            .build()
        
        XCTAssertEqual(artifact.taskIndex, 42)
    }
    
    func testArtifactBuilderTaskIndexParsingWithMetadata() throws {
        // Test task index when metadata is present
        let metadata = TaskMetadataBuilder()
            .withTask(7, "Task seven")
            .build()
        
        let artifact = ArtifactBuilder()
            .withName("task-metadata-project-99.json")  // name suggests index 99
            .withMetadata(metadata)                      // metadata has index 7
            .build()
        
        // Should return index from metadata, not parsed name
        XCTAssertEqual(artifact.taskIndex, 7)
    }
    
    func testArtifactBuilderStaticHelpers() throws {
        // Test static helper methods
        let simpleArtifact = ArtifactBuilder.simple()
        XCTAssertEqual(simpleArtifact.artifactId, 12345)
        XCTAssertEqual(simpleArtifact.artifactName, "task-metadata-sample-project-1.json")
        XCTAssertNil(simpleArtifact.metadata)
        
        let fullArtifact = ArtifactBuilder.withFullMetadata(
            artifactId: 54321,
            taskIndex: 8,
            project: "full-project"
        )
        XCTAssertEqual(fullArtifact.artifactId, 54321)
        XCTAssertEqual(fullArtifact.artifactName, "task-metadata-full-project-8.json")
        XCTAssertNotNil(fullArtifact.metadata)
        XCTAssertEqual(fullArtifact.metadata?.taskIndex, 8)
        XCTAssertEqual(fullArtifact.metadata?.project, "full-project")
    }
    
    func testTaskMetadataBuilderDateHandling() throws {
        // Test custom date setting
        let customDate = TestFixtures.utcDate(year: 2024, month: 12, day: 25, hour: 15, minute: 30)
        
        let metadata = TaskMetadataBuilder()
            .withCreatedAt(customDate)
            .build()
        
        XCTAssertEqual(metadata.createdAt, customDate)
    }
    
    func testBuilderChaining() throws {
        // Test that all methods return self for chaining
        let metadata = TaskMetadataBuilder()
            .withTask(10, "Chain test")
            .withProject("chain-project")
            .withAssignee("charlie")
            .withPRNumber(200)
            .withWorkflowRunId(111222333)
            .withCosts(mainTask: 2.0, prSummary: 0.5)
            .withCreatedAt(TestFixtures.standardTestDate)
            .build()
        
        // Verify all values were set correctly
        XCTAssertEqual(metadata.taskIndex, 10)
        XCTAssertEqual(metadata.taskDescription, "Chain test")
        XCTAssertEqual(metadata.project, "chain-project")
        XCTAssertEqual(metadata.assignee, "charlie")
        XCTAssertEqual(metadata.prNumber, 200)
        XCTAssertEqual(metadata.workflowRunId, 111222333)
        XCTAssertEqual(metadata.mainTaskCostUSD, 2.0)
        XCTAssertEqual(metadata.prSummaryCostUSD, 0.5)
        XCTAssertEqual(metadata.totalCostUSD, 2.5)
        XCTAssertEqual(metadata.createdAt, TestFixtures.standardTestDate)
    }
}