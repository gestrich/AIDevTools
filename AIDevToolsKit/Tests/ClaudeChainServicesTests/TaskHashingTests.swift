/**
 * Unit tests for hash-based task identification edge cases
 * 
 * Swift port of tests/unit/services/test_task_hashing.py
 */

import XCTest
@testable import ClaudeChainServices
@testable import ClaudeChainService
@testable import ClaudeChainInfrastructure

final class TaskHashingTests: XCTestCase {
    
    // MARK: - GenerateTaskHash Tests
    
    func testHashIsStableForSameInput() {
        /// Should generate identical hash for same input
        
        let description = "Add user authentication"
        let hash1 = generateTaskHash(description)
        let hash2 = generateTaskHash(description)
        XCTAssertEqual(hash1, hash2)
    }
    
    func testHashLengthIs8Characters() {
        /// Should generate 8-character hash
        
        let description = "Some task description"
        let taskHash = generateTaskHash(description)
        XCTAssertEqual(taskHash.count, 8)
    }
    
    func testHashIsHexadecimal() {
        /// Should generate hexadecimal hash (0-9, a-f)
        
        let description = "Some task description"
        let taskHash = generateTaskHash(description)
        let hexCharSet = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(taskHash.allSatisfy { hexCharSet.contains($0.unicodeScalars.first!) })
    }
    
    func testHashNormalizesWhitespace() {
        /// Should generate same hash regardless of whitespace
        
        let description1 = "Add user authentication"
        let description2 = "  Add user authentication  "
        let description3 = "Add  user  authentication"
        
        let hash1 = generateTaskHash(description1)
        let hash2 = generateTaskHash(description2)
        let hash3 = generateTaskHash(description3)
        
        // All whitespace is normalized (collapsed to single spaces)
        // Leading/trailing whitespace is stripped
        // Internal whitespace is collapsed
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)  // Internal whitespace is also collapsed
    }
    
    func testHashIsCaseSensitive() {
        /// Should generate different hash for different cases
        
        let description1 = "Add user authentication"
        let description2 = "add user authentication"
        
        let hash1 = generateTaskHash(description1)
        let hash2 = generateTaskHash(description2)
        
        XCTAssertNotEqual(hash1, hash2)
    }
    
    func testHashForEmptyString() {
        /// Should handle empty string
        
        let taskHash = generateTaskHash("")
        XCTAssertEqual(taskHash.count, 8)
        let hexCharSet = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(taskHash.allSatisfy { hexCharSet.contains($0.unicodeScalars.first!) })
    }
    
    func testHashForVeryLongDescription() {
        /// Should handle very long descriptions
        
        let description = String(repeating: "A", count: 1000)  // Very long description
        let taskHash = generateTaskHash(description)
        XCTAssertEqual(taskHash.count, 8)
    }
    
    func testHashForSpecialCharacters() {
        /// Should handle special characters in description
        
        let description = "Update API endpoint `/users/{id}` to support PATCH"
        let taskHash = generateTaskHash(description)
        XCTAssertEqual(taskHash.count, 8)
        let hexCharSet = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(taskHash.allSatisfy { hexCharSet.contains($0.unicodeScalars.first!) })
    }
    
    func testHashForUnicodeCharacters() {
        /// Should handle unicode characters
        
        let description = "Add support for emoji 🎉 and unicode 日本語"
        let taskHash = generateTaskHash(description)
        XCTAssertEqual(taskHash.count, 8)
    }
    
    // MARK: - TaskHashCollisions Tests
    
    func testDifferentTasksHaveDifferentHashes() {
        /// Should generate different hashes for different tasks
        
        let task1 = "Add user authentication"
        let task2 = "Add user authorization"
        let task3 = "Implement feature X"
        
        let hash1 = generateTaskHash(task1)
        let hash2 = generateTaskHash(task2)
        let hash3 = generateTaskHash(task3)
        
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertNotEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
    }
    
    func testSimilarTasksHaveDifferentHashes() {
        /// Should generate different hashes for similar tasks
        
        let task1 = "Fix bug in login"
        let task2 = "Fix bug in logout"
        let task3 = "Fix bug in signup"
        
        let hash1 = generateTaskHash(task1)
        let hash2 = generateTaskHash(task2)
        let hash3 = generateTaskHash(task3)
        
        // All should be different
        let hashSet = Set([hash1, hash2, hash3])
        XCTAssertEqual(hashSet.count, 3)
    }
    
    func testHashDistributionForManyTasks() {
        /// Should generate unique hashes for many similar tasks
        
        // Generate 100 similar tasks
        let tasks = (0..<100).map { "Task number \($0)" }
        let hashes = tasks.map { generateTaskHash($0) }
        
        // All hashes should be unique (no collisions)
        let hashSet = Set(hashes)
        XCTAssertEqual(hashSet.count, hashes.count)
    }
    
    // MARK: - TaskReorderingScenarios Tests
    
    func testTaskHashRemainsStableAfterReordering() {
        /// Task hash should remain stable even when position changes
        
        // Original order
        let project = Project(name: "my-project")
        let content1 = "- [ ] First\n- [ ] Second\n- [ ] Third"
        let spec1 = SpecContent(project: project, content: content1)
        
        let originalFirstHash = spec1.tasks[0].taskHash
        let originalSecondHash = spec1.tasks[1].taskHash
        let originalThirdHash = spec1.tasks[2].taskHash
        
        // Reordered content (Third moved to first position)
        let content2 = "- [ ] Third\n- [ ] First\n- [ ] Second"
        let spec2 = SpecContent(project: project, content: content2)
        
        // Verify hashes are stable despite position change
        XCTAssertEqual(spec2.tasks[0].taskHash, originalThirdHash)  // Third is now first
        XCTAssertEqual(spec2.tasks[1].taskHash, originalFirstHash)  // First is now second
        XCTAssertEqual(spec2.tasks[2].taskHash, originalSecondHash)  // Second is now third
        
        // Verify indices changed but hashes didn't
        XCTAssertEqual(spec2.tasks[0].index, 1)
        XCTAssertEqual(spec2.tasks[1].index, 2)
        XCTAssertEqual(spec2.tasks[2].index, 3)
    }
    
    func testTaskInsertionDoesntAffectExistingHashes() {
        /// Inserting a new task shouldn't affect existing task hashes
        
        // Original tasks
        let project = Project(name: "my-project")
        let content1 = "- [ ] First\n- [ ] Third"
        let spec1 = SpecContent(project: project, content: content1)
        
        let originalFirstHash = spec1.tasks[0].taskHash
        let originalThirdHash = spec1.tasks[1].taskHash
        
        // New task inserted in the middle
        let content2 = "- [ ] First\n- [ ] NEW TASK\n- [ ] Third"
        let spec2 = SpecContent(project: project, content: content2)
        
        // Verify existing task hashes are unchanged
        XCTAssertEqual(spec2.tasks[0].taskHash, originalFirstHash)
        XCTAssertEqual(spec2.tasks[2].taskHash, originalThirdHash)
        
        // Verify new task has a different hash
        let newTaskHash = spec2.tasks[1].taskHash
        XCTAssertNotEqual(newTaskHash, originalFirstHash)
        XCTAssertNotEqual(newTaskHash, originalThirdHash)
    }
    
    func testTaskDeletionDoesntAffectRemainingHashes() {
        /// Deleting a task shouldn't affect remaining task hashes
        
        // Original tasks
        let project = Project(name: "my-project")
        let content1 = "- [ ] First\n- [ ] DELETE ME\n- [ ] Third"
        let spec1 = SpecContent(project: project, content: content1)
        
        let originalFirstHash = spec1.tasks[0].taskHash
        let originalThirdHash = spec1.tasks[2].taskHash
        
        // Middle task deleted
        let content2 = "- [ ] First\n- [ ] Third"
        let spec2 = SpecContent(project: project, content: content2)
        
        // Verify remaining task hashes are unchanged
        XCTAssertEqual(spec2.tasks[0].taskHash, originalFirstHash)
        XCTAssertEqual(spec2.tasks[1].taskHash, originalThirdHash)
    }
    
    // MARK: - OrphanedPRDetection Tests
    
    // TODO: This test requires mocking PRService 
    // func testDetectOrphanedPrsWithHashMismatch() - needs mocked PR service
    
    // TODO: These tests require mocking PRService
    // func testDetectOrphanedPrsWithNoOrphans() - needs mocked PR service
    // func testGetInProgressTasksWithHashBasedPRs() - needs mocked PR service
}