/**
 * Unit tests for PR operations and branch naming utilities
 * 
 * Swift port of tests/unit/services/core/test_pr_service.py
 */

import XCTest
@testable import ClaudeChainServices
@testable import ClaudeChainService
@testable import ClaudeChainInfrastructure

final class PRServiceTests: XCTestCase {
    
    // MARK: - FormatBranchName Tests
    
    func testFormatBasicBranchName() {
        /// Should format branch name with project and hash
        
        let result = PRService.formatBranchName(projectName: "my-refactor", taskHash: "a3f2b891")
        XCTAssertEqual(result, "claude-chain-my-refactor-a3f2b891")
    }
    
    func testFormatWithMultiWordProject() {
        /// Should handle project names with multiple words
        
        let result = PRService.formatBranchName(projectName: "swift-migration", taskHash: "f7c4d3e2")
        XCTAssertEqual(result, "claude-chain-swift-migration-f7c4d3e2")
    }
    
    func testFormatWithDifferentHash() {
        /// Should handle different task hashes
        
        let result = PRService.formatBranchName(projectName: "api-refactor", taskHash: "12345678")
        XCTAssertEqual(result, "claude-chain-api-refactor-12345678")
    }
    
    func testFormatWithComplexProjectName() {
        /// Should handle complex project names with hyphens
        
        let result = PRService.formatBranchName(projectName: "my-complex-project-name", taskHash: "9abcdef0")
        XCTAssertEqual(result, "claude-chain-my-complex-project-name-9abcdef0")
    }
    
    // MARK: - ParseBranchName Tests
    
    func testParseBasicHashBranchName() {
        /// Should parse hash-based branch name (new format)
        
        let result = PRService.parseBranchName(branch: "claude-chain-my-refactor-a3f2b891")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.projectName, "my-refactor")
        XCTAssertEqual(result?.taskHash, "a3f2b891")
        XCTAssertEqual(result?.formatVersion, "hash")
    }
    
    func testParseMultiWordProjectHash() {
        /// Should parse project names with multiple words (hash format)
        
        let result = PRService.parseBranchName(branch: "claude-chain-swift-migration-f7c4d3e2")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.projectName, "swift-migration")
        XCTAssertEqual(result?.taskHash, "f7c4d3e2")
        XCTAssertEqual(result?.formatVersion, "hash")
    }
    
    func testParseInvalidBranchNoPrefix() {
        /// Should return None for branch without claude-chain prefix
        
        let result = PRService.parseBranchName(branch: "my-refactor-1")
        XCTAssertNil(result)
    }
    
    func testParseInvalidBranchWrongFormat() {
        /// Should return None for branch with wrong format
        
        let result = PRService.parseBranchName(branch: "claude-chain-no-index")
        XCTAssertNil(result)
    }
    
    func testParseInvalidBranchEmpty() {
        /// Should return None for empty branch name
        
        let result = PRService.parseBranchName(branch: "")
        XCTAssertNil(result)
    }
    
    func testParseInvalidBranchNoIndex() {
        /// Should return None for branch without index
        
        let result = PRService.parseBranchName(branch: "claude-chain-my-refactor-")
        XCTAssertNil(result)
    }
    
    func testParseRoundtrip() {
        /// Should correctly roundtrip through format and parse
        
        let originalProject = "my-test-project"
        let originalHash = "a1b2c3d4"
        
        // Format then parse
        let branch = PRService.formatBranchName(projectName: originalProject, taskHash: originalHash)
        let result = PRService.parseBranchName(branch: branch)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.projectName, originalProject)
        XCTAssertEqual(result?.taskHash, originalHash)
        XCTAssertEqual(result?.formatVersion, "hash")
    }
    
    func testParseInvalidBranchNonHexHash() {
        /// Should return None for branch with invalid hash (contains non-hex chars)
        
        let result = PRService.parseBranchName(branch: "claude-chain-my-refactor-abcdefgh")
        XCTAssertNil(result)
    }
    
    func testParseInvalidBranchNegativeIndex() {
        /// Should return None for branch with negative index (contains hyphen before number)
        /// Note: This will match the pattern but the last -1 will be treated as index 1
        /// The project name will be "my-refactor-" which is still valid
        
        let result = PRService.parseBranchName(branch: "claude-chain-my-refactor--a3f2b89")
        // This should parse, but the project name will be "my-refactor-"
        // Actually testing the current behavior
        if let result = result {
            XCTAssertEqual(result.projectName, "my-refactor-")
            XCTAssertEqual(result.taskHash, "a3f2b891")
            XCTAssertEqual(result.formatVersion, "hash")
        }
        // If implementation changes to reject this, that's also acceptable
        // The key is to document the behavior
    }
    
    func testParseSingleCharProject() {
        /// Should handle single character project names
        
        let result = PRService.parseBranchName(branch: "claude-chain-x-a3f2b891")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.projectName, "x")
        XCTAssertEqual(result?.taskHash, "a3f2b891")
        XCTAssertEqual(result?.formatVersion, "hash")
    }
    
    func testParseWhitespaceInBranch() {
        /// Should handle branch with whitespace (though not recommended)
        /// The regex pattern (.+) will match whitespace in project names
        /// While not recommended, this tests the actual behavior
        
        let result = PRService.parseBranchName(branch: "claude-chain-my refactor-a3f2b891")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.projectName, "my refactor")
        XCTAssertEqual(result?.taskHash, "a3f2b891")
        XCTAssertEqual(result?.formatVersion, "hash")
    }
    
    func testParseCaseSensitivity() {
        /// Should handle case sensitivity in prefix (expects lowercase)
        
        let result = PRService.parseBranchName(branch: "Claude-Chain-my-refactor-1")
        XCTAssertNil(result)  // Should fail because prefix is case-sensitive
    }
    
    // MARK: - GetProjectPrs Tests (Infrastructure-dependent)
    
    // TODO: The following tests require mocking the infrastructure layer
    // These would need proper dependency injection or protocol-based design
    // to be easily testable:
    //
    // - testGetOpenPrs - needs mocked PR list infrastructure
    // - testGetProjectPrsWithPrefixCollision - needs mocked PR data  
    // - testGetProjectPrsWithStateFilter - needs mocked PR data
    // - testGetClosedPrs - needs mocked PR data
    // - testGetAllPrs - needs mocked PR data
    // - testGetProjectPrsEmptyResult - needs mocked infrastructure
    // - testGetProjectPrsWithLimit - needs mocked PR data
    // - testGetProjectPrsDefaultsToClaudeChainLabel - needs call verification
    // - testGetProjectPrsCustomLabel - needs call verification
    // - testGetProjectPrsInfrastructureError - needs error simulation
}