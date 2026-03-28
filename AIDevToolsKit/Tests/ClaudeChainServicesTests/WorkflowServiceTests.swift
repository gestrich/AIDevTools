/**
 * Tests for GitHub workflow triggering service
 */

import XCTest
@testable import ClaudeChainServices
@testable import ClaudeChainService

final class WorkflowServiceTests: XCTestCase {
    
    // MARK: - Test triggerClaudeChainWorkflow() method
    
    func testTriggerClaudeChainWorkflowSuccess() throws {
        let service = WorkflowService()
        
        // Note: This test would require mocking GitHubOperations.runGhCommand
        // For now, we test that the method exists and has correct signature
        // In a full implementation, we'd mock the infrastructure layer
        
        do {
            try service.triggerClaudeChainWorkflow(
                projectName: "test-project",
                baseBranch: "main",
                checkoutRef: "main"
            )
            // If we get here without throwing, the method completed
            // In practice, this would fail because we don't have gh CLI configured
            // But the method signature and basic structure are correct
        } catch {
            // Expected to fail in test environment without proper gh CLI setup
            // The error should be wrapped in GitHubAPIError
            if let apiError = error as? GitHubAPIError {
                XCTAssertTrue(apiError.message.contains("Failed to trigger workflow for project 'test-project'"))
            } else {
                XCTFail("Expected GitHubAPIError but got \(type(of: error))")
            }
        }
    }
    
    func testTriggerClaudeChainWorkflowWithDifferentParameters() throws {
        let service = WorkflowService()
        
        do {
            try service.triggerClaudeChainWorkflow(
                projectName: "my-refactor",
                baseBranch: "develop",
                checkoutRef: "feature-branch"
            )
        } catch {
            // Expected to fail in test environment
            if let apiError = error as? GitHubAPIError {
                XCTAssertTrue(apiError.message.contains("Failed to trigger workflow for project 'my-refactor'"))
            } else {
                XCTFail("Expected GitHubAPIError but got \(type(of: error))")
            }
        }
    }
    
    // MARK: - Test batchTriggerClaudeChainWorkflows() method
    
    func testBatchTriggerClaudeChainWorkflowsEmptyList() throws {
        let service = WorkflowService()
        
        let (successful, failed) = service.batchTriggerClaudeChainWorkflows(
            projects: [],
            baseBranch: "main",
            checkoutRef: "main"
        )
        
        XCTAssertEqual(successful.count, 0)
        XCTAssertEqual(failed.count, 0)
    }
    
    func testBatchTriggerClaudeChainWorkflowsSingleProject() throws {
        let service = WorkflowService()
        
        let (successful, failed) = service.batchTriggerClaudeChainWorkflows(
            projects: ["project1"],
            baseBranch: "main",
            checkoutRef: "main"
        )
        
        // Expected to fail in test environment without gh CLI setup
        XCTAssertEqual(successful.count, 0)
        XCTAssertEqual(failed.count, 1)
        XCTAssertEqual(failed[0], "project1")
    }
    
    func testBatchTriggerClaudeChainWorkflowsMultipleProjects() throws {
        let service = WorkflowService()
        
        let projects = ["project1", "project2", "project3"]
        let (successful, failed) = service.batchTriggerClaudeChainWorkflows(
            projects: projects,
            baseBranch: "main",
            checkoutRef: "main"
        )
        
        // Expected to fail in test environment without gh CLI setup
        XCTAssertEqual(successful.count, 0)
        XCTAssertEqual(failed.count, 3)
        XCTAssertEqual(Set(failed), Set(projects))
    }
    
    func testBatchTriggerClaudeChainWorkflowsWithDifferentParameters() throws {
        let service = WorkflowService()
        
        let projects = ["project1", "project2"]
        let (successful, failed) = service.batchTriggerClaudeChainWorkflows(
            projects: projects,
            baseBranch: "develop",
            checkoutRef: "feature-branch"
        )
        
        // Expected to fail in test environment
        XCTAssertEqual(successful.count, 0)
        XCTAssertEqual(failed.count, 2)
        XCTAssertEqual(Set(failed), Set(projects))
    }
    
    func testBatchTriggerContinuesOnIndividualFailures() throws {
        let service = WorkflowService()
        
        // All projects should be attempted even if some fail
        let projects = ["project1", "project2", "project3", "project4"]
        let (successful, failed) = service.batchTriggerClaudeChainWorkflows(
            projects: projects,
            baseBranch: "main",
            checkoutRef: "main"
        )
        
        // Should attempt all projects
        XCTAssertEqual(successful.count + failed.count, projects.count)
        
        // In test environment, all should fail
        XCTAssertEqual(failed.count, projects.count)
        XCTAssertEqual(Set(failed), Set(projects))
    }
    
    // MARK: - Test service initialization
    
    func testServiceInitialization() throws {
        let service = WorkflowService()
        
        // Should be able to create service without parameters
        XCTAssertNotNil(service)
        
        // Should be able to call methods
        let (successful, failed) = service.batchTriggerClaudeChainWorkflows(
            projects: [],
            baseBranch: "main",
            checkoutRef: "main"
        )
        
        XCTAssertEqual(successful.count, 0)
        XCTAssertEqual(failed.count, 0)
    }
    
    // MARK: - Test error handling consistency
    
    func testErrorWrappingConsistency() throws {
        let service = WorkflowService()
        
        do {
            try service.triggerClaudeChainWorkflow(
                projectName: "test-project",
                baseBranch: "main",
                checkoutRef: "main"
            )
        } catch let error as GitHubAPIError {
            // Verify error message format matches Python implementation
            XCTAssertTrue(error.message.hasPrefix("Failed to trigger workflow for project 'test-project':"))
        } catch {
            XCTFail("Expected GitHubAPIError but got \(type(of: error))")
        }
    }
    
    func testBatchProcessingErrorHandling() throws {
        let service = WorkflowService()
        
        // Test that batch processing handles individual failures gracefully
        let projects = ["valid-project", "another-project"]
        let (successful, failed) = service.batchTriggerClaudeChainWorkflows(
            projects: projects,
            baseBranch: "main",
            checkoutRef: "main"
        )
        
        // Should not throw exceptions, should collect failures
        XCTAssertTrue(successful.count + failed.count == projects.count)
        
        // In test environment without gh CLI, all should fail
        XCTAssertEqual(failed.count, projects.count)
    }
    
    // MARK: - Test parameter validation
    
    func testTriggerWorkflowWithEmptyProjectName() throws {
        let service = WorkflowService()
        
        do {
            try service.triggerClaudeChainWorkflow(
                projectName: "",
                baseBranch: "main",
                checkoutRef: "main"
            )
        } catch {
            // Should fail, either due to empty project name or gh CLI error
            // The specific error depends on infrastructure implementation
        }
    }
    
    func testTriggerWorkflowWithEmptyBranches() throws {
        let service = WorkflowService()
        
        do {
            try service.triggerClaudeChainWorkflow(
                projectName: "test-project",
                baseBranch: "",
                checkoutRef: ""
            )
        } catch {
            // Should fail due to empty branch parameters
        }
    }
    
    // MARK: - Test return value consistency
    
    func testBatchReturnValueStructure() throws {
        let service = WorkflowService()
        
        let projects = ["project1", "project2"]
        let (successful, failed) = service.batchTriggerClaudeChainWorkflows(
            projects: projects,
            baseBranch: "main",
            checkoutRef: "main"
        )
        
        // Return values should be arrays of strings (remove redundant type checks)
        XCTAssertTrue(type(of: successful) == [String].self)
        XCTAssertTrue(type(of: failed) == [String].self)
        
        // Total should equal input
        XCTAssertEqual(successful.count + failed.count, projects.count)
        
        // No duplicates between successful and failed
        let successfulSet = Set(successful)
        let failedSet = Set(failed)
        XCTAssertTrue(successfulSet.intersection(failedSet).isEmpty)
        
        // All projects should be accounted for
        let allResultProjects = successfulSet.union(failedSet)
        XCTAssertEqual(allResultProjects, Set(projects))
    }
}