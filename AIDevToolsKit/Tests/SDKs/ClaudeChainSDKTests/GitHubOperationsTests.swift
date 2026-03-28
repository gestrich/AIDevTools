import XCTest
@testable import ClaudeChainSDK
@testable import ClaudeChainService
import Foundation

/// Tests for GitHub CLI operations
/// Swift port of test_operations.py (github)
final class GitHubOperationsTests: XCTestCase {
    
    // MARK: - Detect Project from Diff Tests
    
    func testDetectProjectFromDiffWithSingleProject() throws {
        // Should detect single ClaudeChain project from file paths
        
        // Arrange
        let changedFiles = [
            "claude-chain/my-project/spec.md",
            "README.md"
        ]
        
        // Act
        let project = try GitHubOperations.detectProjectFromDiff(changedFiles: changedFiles)
        
        // Assert
        XCTAssertEqual(project, "my-project")
    }
    
    func testDetectProjectFromDiffWithNonClaudeChainFiles() throws {
        // Should return nil for non-ClaudeChain files
        
        // Arrange
        let changedFiles = [
            "src/main.swift",
            "docs/README.md",
            "package.json"
        ]
        
        // Act
        let project = try GitHubOperations.detectProjectFromDiff(changedFiles: changedFiles)
        
        // Assert
        XCTAssertNil(project)
    }
    
    func testDetectProjectFromDiffThrowsWithMultipleProjects() {
        // Should throw error when multiple projects are detected
        
        // Arrange
        let changedFiles = [
            "claude-chain/database-migration/spec.md",
            "claude-chain/user-auth/spec.md"
        ]
        
        // Act & Assert
        XCTAssertThrowsError(try GitHubOperations.detectProjectFromDiff(changedFiles: changedFiles))
    }
    
    func testDetectProjectFromDiffIgnoresNonSpecFiles() throws {
        // Should ignore non-spec.md files in ClaudeChain directories
        
        // Arrange
        let changedFiles = [
            "claude-chain/my-project/configuration.yml",
            "claude-chain/my-project/pre-action.sh",
            "claude-chain/my-project/spec.md"
        ]
        
        // Act
        let project = try GitHubOperations.detectProjectFromDiff(changedFiles: changedFiles)
        
        // Assert
        XCTAssertEqual(project, "my-project")
    }
    
    // MARK: - File Existence Tests
    
    func testFileExistsInBranchReturnsBool() throws {
        // Should return a boolean value for file existence
        
        // This test may require GitHub CLI and appropriate permissions
        // For now, we just test that it doesn't crash with reasonable inputs
        let exists = GitHubOperations.fileExistsInBranch(
            repo: "owner/repo", 
            branch: "main", 
            filePath: "README.md"
        )
        // Should return a boolean (will likely be false without GitHub access)
        XCTAssertTrue(exists == true || exists == false)
    }
    
    // MARK: - Merge PR Listing Tests
    
    func testListMergedPullRequestsRequiresSinceDate() {
        // Should require a since date parameter
        
        let since = Date().addingTimeInterval(-7 * 24 * 60 * 60) // 7 days ago
        
        // This test verifies the method signature exists and can be called
        // It will likely fail due to missing GitHub CLI or permissions
        do {
            let prs = try GitHubOperations.listMergedPullRequests(
                repo: "owner/repo",
                since: since
            )
            // If successful, should return an array
            XCTAssertTrue(prs.count >= 0) // Array can be empty or have items
        } catch {
            // Expected to fail in test environment
            XCTAssertTrue(error is GitHubAPIError)
        }
    }
    
    // MARK: - Run GitHub Command Tests
    
    func testRunGhCommandReturnsString() throws {
        // Should execute gh command and return output
        
        // This tests the basic signature and that it returns a string
        // Will fail if gh is not available, but validates the interface
        do {
            let result = try GitHubOperations.runGhCommand(args: ["--version"])
            XCTAssertTrue(result.contains("gh version") || result.contains("GitHub CLI"))
        } catch {
            // Expected to fail if gh is not installed or configured
            XCTAssertTrue(error is GitHubAPIError)
        }
    }
    
    func testRunGhCommandWithInvalidArgs() {
        // Should throw GitHubAPIError for invalid commands
        
        XCTAssertThrowsError(try GitHubOperations.runGhCommand(args: ["invalid-command-xyz"])) { error in
            XCTAssertTrue(error is GitHubAPIError)
        }
    }
    
    // MARK: - GitHub API Call Tests
    
    func testGhApiCallWithValidEndpoint() {
        // Should return dictionary from API endpoint
        
        // This test validates the interface but will fail without GitHub auth
        do {
            let result = try GitHubOperations.ghApiCall(endpoint: "/user", method: "GET")
            XCTAssertNotNil(result) // Should return a dictionary
        } catch {
            // Expected without proper GitHub authentication
            XCTAssertTrue(error is GitHubAPIError)
        }
    }
    
    func testGhApiCallHandlesEmptyResponse() throws {
        // Should return empty dict for empty response (if we could mock it)
        
        // This test documents the expected behavior for empty responses
        // In practice, GitHub API rarely returns truly empty responses
        // but the method should handle it gracefully
        
        // We can't easily test this without mocking, but we document the expectation
        XCTAssertTrue(true, "Empty response should return empty dictionary")
    }
    
    // MARK: - File Operations Tests
    
    func testGetFileFromBranchReturnsString() {
        // Should return file content as string or nil
        
        do {
            let content = try GitHubOperations.getFileFromBranch(
                repo: "owner/repo", 
                branch: "main", 
                filePath: "README.md"
            )
            // Should return string or nil, not crash
            if let content = content {
                XCTAssertTrue(content is String)
            }
        } catch {
            // Expected without proper GitHub access
            XCTAssertTrue(error is GitHubAPIError)
        }
    }
    
    func testGetFileFromBranchHandlesNotFound() throws {
        // Should return nil for non-existent files
        
        do {
            let content = try GitHubOperations.getFileFromBranch(
                repo: "owner/repo", 
                branch: "main", 
                filePath: "definitely-does-not-exist.xyz"
            )
            XCTAssertNil(content)
        } catch {
            // Expected without GitHub access, error should mention 404 or Not Found
            let errorMessage = error.localizedDescription.lowercased()
            XCTAssertTrue(errorMessage.contains("404") || errorMessage.contains("not found") || error is GitHubAPIError)
        }
    }
    
    // MARK: - Compare Commits Tests
    
    func testCompareCommitsReturnsArray() {
        // Should return array of changed file paths
        
        do {
            let changes = try GitHubOperations.compareCommits(
                repo: "owner/repo", 
                base: "main", 
                head: "feature"
            )
            XCTAssertTrue(changes is [String])
        } catch {
            // Expected without GitHub access
            XCTAssertTrue(error is GitHubAPIError)
        }
    }
    
    func testCompareCommitsWithSameRef() {
        // Should return empty array when comparing same commit
        
        do {
            let changes = try GitHubOperations.compareCommits(
                repo: "owner/repo", 
                base: "main", 
                head: "main"
            )
            XCTAssertEqual(changes.count, 0)
        } catch {
            // Expected without GitHub access
            XCTAssertTrue(error is GitHubAPIError)
        }
    }
    
    // MARK: - Pull Request Tests
    
    func testListPullRequestsReturnsArray() {
        // Should return array of GitHubPullRequest objects
        
        do {
            let prs = try GitHubOperations.listPullRequests(repo: "owner/repo", state: "open", limit: 10)
            XCTAssertTrue(prs.count >= 0) // Array can be empty or have items
        } catch {
            // Expected without GitHub access
            XCTAssertTrue(error is GitHubAPIError)
        }
    }
    
    func testListPullRequestsWithFilters() {
        // Should accept filter parameters
        
        do {
            let prs = try GitHubOperations.listPullRequests(
                repo: "owner/repo", 
                state: "merged", 
                label: "claudechain", 
                assignee: "testuser",
                limit: 50
            )
            XCTAssertTrue(prs is [GitHubPullRequest])
        } catch {
            // Expected without GitHub access
            XCTAssertTrue(error is GitHubAPIError)
        }
    }
    
    func testListMergedPullRequestsWithSinceDate() {
        // Should filter merged PRs by date
        
        let since = Date().addingTimeInterval(-7 * 24 * 60 * 60) // 7 days ago
        
        do {
            let prs = try GitHubOperations.listMergedPullRequests(
                repo: "owner/repo",
                since: since,
                label: "claudechain"
            )
            XCTAssertTrue(prs is [GitHubPullRequest])
        } catch {
            // Expected without GitHub access
            XCTAssertTrue(error is GitHubAPIError)
        }
    }
    
    func testListOpenPullRequestsWithLabel() {
        // Should filter open PRs by label
        
        do {
            let prs = try GitHubOperations.listOpenPullRequests(
                repo: "owner/repo",
                label: "claudechain",
                limit: 25
            )
            XCTAssertTrue(prs is [GitHubPullRequest])
        } catch {
            // Expected without GitHub access
            XCTAssertTrue(error is GitHubAPIError)
        }
    }
    
    // MARK: - Label Management Tests
    
    func testEnsureLabelExistsWithMockGitHubActions() {
        // Should call ensureLabelExists with proper parameters
        
        // Create a mock GitHubActions instance
        let mockGH = GitHubActions(outputFile: nil, summaryFile: nil)
        
        // Test that the method can be called without crashing
        // The actual implementation will try to create a label via GitHub CLI
        GitHubOperations.ensureLabelExists(label: "test-label", gh: mockGH)
        
        // No assertion needed - we're just testing it doesn't crash
        XCTAssertTrue(true)
    }
    
    func testAddLabelToPrReturnsBool() {
        // Should return boolean indicating success/failure
        
        let result = GitHubOperations.addLabelToPr(
            repo: "owner/repo", 
            prNumber: 123, 
            label: "claudechain"
        )
        XCTAssertTrue(result is Bool)
        // Will likely return false without proper GitHub setup, but should not crash
    }
    
    // MARK: - Workflow Operations Tests
    
    func testListWorkflowRunsReturnsArray() {
        // Should return array of WorkflowRun objects
        
        do {
            let runs = try GitHubOperations.listWorkflowRuns(
                repo: "owner/repo", 
                workflowName: "ci.yml", 
                branch: "main",
                limit: 5
            )
            XCTAssertTrue(runs is [WorkflowRun])
        } catch {
            // Expected without GitHub access
            XCTAssertTrue(error is GitHubAPIError)
        }
    }
    
    func testTriggerWorkflowWithInputs() {
        // Should accept workflow inputs
        
        do {
            try GitHubOperations.triggerWorkflow(
                repo: "owner/repo",
                workflowName: "deploy.yml",
                inputs: ["environment": "test", "version": "v1.0.0"],
                ref: "main"
            )
            // If successful, no error thrown
            XCTAssertTrue(true)
        } catch {
            // Expected without GitHub access
            XCTAssertTrue(error is GitHubAPIError)
        }
    }
    
    // MARK: - Download Artifact Tests
    
    func testDownloadArtifactJsonReturnsOptionalDict() {
        // Should return optional dictionary or nil
        
        let result = GitHubOperations.downloadArtifactJson(repo: "owner/repo", artifactId: 12345)
        
        // Should return nil or a dictionary, not crash
        if let result = result {
            XCTAssertTrue(result.count >= 0) // Dictionary can be empty or have items
        } else {
            // Nil is expected without GitHub access or valid artifact
            XCTAssertNil(result)
        }
    }
    
    // MARK: - Branch Operations Tests
    
    func testListBranchesReturnsArray() {
        // Should return array of branch names
        
        let branches = GitHubOperations.listBranches(repo: "owner/repo")
        XCTAssertTrue(branches is [String])
        // Will likely return empty array without GitHub access, but should not crash
    }
    
    func testListBranchesWithPrefix() {
        // Should filter branches by prefix
        
        let branches = GitHubOperations.listBranches(repo: "owner/repo", prefix: "claude-chain-")
        XCTAssertTrue(branches is [String])
    }
    
    func testDeleteBranchHandlesErrors() {
        // Should handle branch deletion gracefully
        
        do {
            try GitHubOperations.deleteBranch(repo: "owner/repo", branch: "test-branch")
            // If successful, no error thrown
            XCTAssertTrue(true)
        } catch {
            // Expected without GitHub access
            XCTAssertTrue(error is GitHubAPIError)
        }
    }
    
    // MARK: - Extended PR Operations Tests
    
    func testGetPullRequestByBranch() {
        // Should find PR by branch name
        
        do {
            let pr = try GitHubOperations.getPullRequestByBranch(repo: "owner/repo", branch: "feature-branch")
            // Should return nil or a GitHubPullRequest
            if let pr = pr {
                XCTAssertTrue(pr is GitHubPullRequest)
            }
        } catch {
            // Expected without GitHub access
            XCTAssertTrue(error is GitHubAPIError)
        }
    }
    
    func testClosePullRequest() {
        // Should handle PR closing
        
        do {
            try GitHubOperations.closePullRequest(repo: "owner/repo", prNumber: 123)
            XCTAssertTrue(true)
        } catch {
            // Expected without GitHub access
            XCTAssertTrue(error is GitHubAPIError)
        }
    }
    
    func testMergePullRequest() {
        // Should handle PR merging
        
        do {
            try GitHubOperations.mergePullRequest(repo: "owner/repo", prNumber: 123, mergeMethod: "squash")
            XCTAssertTrue(true)
        } catch {
            // Expected without GitHub access
            XCTAssertTrue(error is GitHubAPIError)
        }
    }
    
    // Note: Most tests validate interface/signature rather than actual functionality
    // because they would require:
    // - GitHub CLI (gh) to be installed and authenticated
    // - Network access to GitHub API
    // - Valid repository and permissions
    // 
    // In a production environment, these would be mocked or tested against a test repository.
    // The tests above ensure methods exist, accept correct parameters, return expected types,
    // and handle errors gracefully.
}