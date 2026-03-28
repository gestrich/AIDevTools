/**
 * Shared test fixtures and helpers
 * 
 * Swift port of useful patterns from tests/conftest.py
 * Provides common test data and setup helpers for ClaudeChain tests.
 */

import Foundation
import XCTest
import ClaudeChainService
import ClaudeChainServices

/// Shared test fixtures and helpers for ClaudeChain tests
///
/// This class provides static methods for creating commonly used test data
/// and temporary file structures. Unlike pytest fixtures, these are called
/// explicitly in test methods.
public class TestFixtures {
    
    // MARK: - File System Helpers
    
    /// Create a temporary project directory structure
    ///
    /// Creates:
    /// - claude-chain/ directory
    /// - claude-chain/project-name/ subdirectory
    ///
    /// - Parameter projectName: Name of the project subdirectory
    /// - Returns: URL to the claude-chain directory
    /// - Throws: File system errors
    public static func createTmpProjectDir(projectName: String = "project-name") throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let claudeChainDir = tempDir.appendingPathComponent("claude-chain")
        let projectDir = claudeChainDir.appendingPathComponent(projectName)
        
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        
        return claudeChainDir
    }
    
    /// Create a sample spec.md file with various task states
    ///
    /// - Parameter directory: Directory to create the file in
    /// - Returns: URL to the created spec.md file
    /// - Throws: File system errors
    public static func createSampleSpecFile(in directory: URL) throws -> URL {
        let specContent = """
# Project Specification

This is a sample project for testing.

## Tasks

- [x] Task 1 - Completed task
- [x] Task 2 - Another completed task  
- [ ] Task 3 - Next task to do
- [ ] Task 4 - Future task
- [ ] Task 5 - Another future task
"""
        
        let specFile = directory.appendingPathComponent("spec.md")
        try specContent.write(to: specFile, atomically: true, encoding: .utf8)
        return specFile
    }
    
    /// Create an empty spec.md file (no tasks)
    ///
    /// - Parameter directory: Directory to create the file in
    /// - Returns: URL to the created spec.md file
    /// - Throws: File system errors
    public static func createEmptySpecFile(in directory: URL) throws -> URL {
        let specContent = """
# Project Specification

This project has no tasks yet.
"""
        
        let specFile = directory.appendingPathComponent("spec.md")
        try specContent.write(to: specFile, atomically: true, encoding: .utf8)
        return specFile
    }
    
    /// Create a spec.md file with all tasks completed
    ///
    /// - Parameter directory: Directory to create the file in
    /// - Returns: URL to the created spec.md file
    /// - Throws: File system errors
    public static func createAllCompletedSpecFile(in directory: URL) throws -> URL {
        let specContent = """
# Project Specification

## Tasks

- [x] Task 1 - Completed
- [x] Task 2 - Completed
- [x] Task 3 - Completed
"""
        
        let specFile = directory.appendingPathComponent("spec.md")
        try specContent.write(to: specFile, atomically: true, encoding: .utf8)
        return specFile
    }
    
    /// Create a sample configuration.yml file
    ///
    /// - Parameter directory: Directory to create the file in
    /// - Returns: URL to the created configuration.yml file
    /// - Throws: File system errors
    public static func createSampleConfigFile(in directory: URL) throws -> URL {
        let configContent = """
reviewers:
  - username: alice
    maxOpenPRs: 2
  - username: bob
    maxOpenPRs: 3
  - username: charlie
    maxOpenPRs: 1

project: sample-project
"""
        
        let configFile = directory.appendingPathComponent("configuration.yml")
        try configContent.write(to: configFile, atomically: true, encoding: .utf8)
        return configFile
    }
    
    // MARK: - GitHub Test Data
    
    /// Sample PR data for testing
    ///
    /// - Returns: Dictionary with sample PR response data from GitHub API
    public static func samplePRData() -> [String: Any] {
        return PRDataBuilder()
            .withNumber(123)
            .withTask("a3f2b891", "Implement feature", project: "my-project")
            .withUser("alice")
            .withCreatedAt("2025-01-15T10:00:00Z")
            .build()
            .asDictionary()
    }
    
    /// Sample list of PRs for testing
    ///
    /// - Returns: List of PR data dicts with various states
    public static func samplePRList() -> [[String: Any]] {
        return [
            [
                "number": 101,
                "title": "Task 1 - First task",
                "state": "closed",
                "merged": true,
                "head": ["ref": "claude-chain-my-project-a1b2c3d4"],
                "labels": [["name": "claude-chain"]]
            ],
            [
                "number": 102,
                "title": "Task 2 - Second task",
                "state": "open",
                "merged": false,
                "head": ["ref": "claude-chain-my-project-b2c3d4e5"],
                "labels": [["name": "claude-chain"]]
            ],
            [
                "number": 103,
                "title": "Task 3 - Third task",
                "state": "open",
                "merged": false,
                "head": ["ref": "claude-chain-my-project-c3d4e5f6"],
                "labels": [["name": "claude-chain"]]
            ]
        ]
    }
    
    // MARK: - Configuration Test Data
    
    /// Sample reviewer configuration
    ///
    /// - Returns: List of reviewer configuration dicts
    public static func sampleReviewerConfig() -> [[String: Any]] {
        return [
            ["username": "alice", "maxOpenPRs": 2],
            ["username": "bob", "maxOpenPRs": 3],
            ["username": "charlie", "maxOpenPRs": 1]
        ]
    }
    
    /// Sample task metadata
    ///
    /// - Returns: Dict with task metadata structure
    public static func sampleTaskMetadata() -> [String: Any] {
        return [
            "task_index": 3,
            "task_description": "Implement feature X",
            "project": "my-project",
            "reviewer": "alice",
            "branch": "claude-chain-my-project-c3d4e5f6",
            "created_at": "2025-01-15T10:00:00Z"
        ]
    }
    
    /// Sample prompt template with placeholders
    ///
    /// - Returns: String with template placeholders
    public static func samplePromptTemplate() -> String {
        return """
You are analyzing a pull request.

## Context
- Task: {TASK_DESCRIPTION}
- PR: #{PR_NUMBER}
- Project: {PROJECT}
- Workflow: {WORKFLOW_URL}

## Instructions
Review the changes and provide feedback.
"""
    }
    
    // MARK: - Date Helpers
    
    /// Create a UTC date from components for consistent test data
    ///
    /// - Parameters:
    ///   - year: Year
    ///   - month: Month (1-12)
    ///   - day: Day
    ///   - hour: Hour (default: 10)
    ///   - minute: Minute (default: 0)
    ///   - second: Second (default: 0)
    /// - Returns: Date in UTC timezone
    public static func utcDate(
        year: Int,
        month: Int, 
        day: Int,
        hour: Int = 10,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        let calendar = Calendar.current
        let components = DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        )
        return calendar.date(from: components) ?? Date()
    }
    
    /// Standard test date used in Python tests: 2025-01-15T10:00:00Z
    public static let standardTestDate = utcDate(year: 2025, month: 1, day: 15)
}

// MARK: - XCTest Extensions

extension XCTestCase {
    
    /// Create a temporary directory for test files
    ///
    /// The directory will be cleaned up automatically when the test ends.
    ///
    /// - Returns: URL to the temporary directory
    func createTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        return tempDir
    }
}

// MARK: - GitHubPullRequest Extensions for Testing

extension GitHubPullRequest {
    /// Convert to dictionary representation for API compatibility
    ///
    /// This is useful when tests need to work with the dictionary format
    /// that would come from GitHub API responses.
    ///
    /// - Returns: Dictionary representation of the PR
    func asDictionary() -> [String: Any] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        var result: [String: Any] = [
            "number": number,
            "title": title,
            "state": state,
            "createdAt": dateFormatter.string(from: createdAt),
            "assignees": assignees.map { ["login": $0.login, "name": $0.name ?? ""] },
            "labels": labels.map { ["name": $0] }
        ]
        
        if let mergedAt = mergedAt {
            result["mergedAt"] = dateFormatter.string(from: mergedAt)
        }
        
        if let headRefName = headRefName {
            result["headRefName"] = headRefName
        }
        
        if let baseRefName = baseRefName {
            result["baseRefName"] = baseRefName
        }
        
        if let url = url {
            result["url"] = url
        }
        
        return result
    }
}