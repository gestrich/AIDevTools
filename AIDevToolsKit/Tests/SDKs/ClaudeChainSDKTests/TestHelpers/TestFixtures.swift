import ClaudeChainService
import Foundation
import XCTest

/// Test fixtures providing common test data and setup
/// Swift port of Python pytest fixtures

public class TestFixtures {
    
    // MARK: - File System Fixtures
    
    /// Create a temporary project directory structure
    /// Creates: claude-chain/ directory with project-name/ subdirectory
    public static func createTempProjectDir() -> (URL, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-chain-tests")
            .appendingPathComponent(UUID().uuidString)
        
        let claudeChainDir = tempDir.appendingPathComponent("claude-chain")
        let projectDir = claudeChainDir.appendingPathComponent("project-name")
        
        try! FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        
        return (claudeChainDir, projectDir)
    }
    
    /// Create a sample spec.md file with various task states
    public static func createSampleSpecFile(in directory: URL) -> URL {
        return SpecFileBuilder()
            .withTitle("Project Specification")
            .withOverview("This is a sample project for testing.")
            .addSection("## Tasks")
            .addCompletedTask("Task 1 - Completed task")
            .addCompletedTask("Task 2 - Another completed task")
            .addTask("Task 3 - Next task to do")
            .addTask("Task 4 - Future task")
            .addTask("Task 5 - Another future task")
            .writeTo(directory)
    }
    
    /// Create an empty spec.md file (no tasks)
    public static func createEmptySpecFile(in directory: URL) -> URL {
        return SpecFileBuilder()
            .withTitle("Project Specification")
            .withOverview("This project has no tasks yet.")
            .writeTo(directory)
    }
    
    /// Create a spec.md file with all tasks completed
    public static func createAllCompletedSpecFile(in directory: URL) -> URL {
        return SpecFileBuilder()
            .withTitle("Project Specification")
            .addSection("## Tasks")
            .addCompletedTask("Task 1 - Completed")
            .addCompletedTask("Task 2 - Completed")
            .addCompletedTask("Task 3 - Completed")
            .writeTo(directory)
    }
    
    /// Create a sample configuration.yml file
    public static func createSampleConfigFile(in directory: URL) -> URL {
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
        try! configContent.write(to: configFile, atomically: true, encoding: .utf8)
        return configFile
    }
    
    /// Create config file with deprecated branchPrefix field
    public static func createConfigWithDeprecatedField(in directory: URL) -> URL {
        let configContent = """
reviewers:
  - username: alice
    maxOpenPRs: 2

branchPrefix: custom-prefix
"""
        let configFile = directory.appendingPathComponent("configuration.yml")
        try! configContent.write(to: configFile, atomically: true, encoding: .utf8)
        return configFile
    }
    
    // MARK: - Mock Data Fixtures
    
    /// Sample PR data for testing
    public static func samplePRData() -> [String: Any] {
        return PRDataBuilder()
            .withNumber(123)
            .withTask(3, "Implement feature", "my-project")
            .withUser("alice")
            .withCreatedAt("2025-01-15T10:00:00Z")
            .build()
    }
    
    /// Sample configuration dictionary
    public static func sampleConfigDict() -> [String: Any] {
        return ConfigBuilder.default()
    }
    
    /// Single reviewer configuration
    public static func singleReviewerConfig() -> [String: Any] {
        return ConfigBuilder().withAssignee("alice").build()
    }
    
    /// Configuration with no reviewers
    public static func noReviewersConfig() -> [String: Any] {
        return [
            "reviewers": [],
            "project": "sample-project"
        ]
    }
    
    /// Sample reviewer configuration objects
    public static func sampleReviewerConfig() -> [[String: Any]] {
        return [
            ["username": "alice", "maxOpenPRs": 2],
            ["username": "bob", "maxOpenPRs": 3],
            ["username": "charlie", "maxOpenPRs": 1]
        ]
    }
    
    /// Sample task metadata
    public static func sampleTaskMetadata() -> [String: Any] {
        return [
            "task_index": 3,
            "task_description": "Implement feature X",
            "project": "my-project",
            "reviewer": "alice",
            "branch": "claude-chain-my-project-3",
            "created_at": "2025-01-15T10:00:00Z"
        ]
    }
    
    /// List of sample PRs for testing
    public static func samplePRList() -> [[String: Any]] {
        return [
            [
                "number": 101,
                "title": "Task 1 - First task",
                "state": "closed",
                "merged": true,
                "head": ["ref": "claude-chain-my-project-1"],
                "labels": [["name": "claude-chain"]]
            ],
            [
                "number": 102,
                "title": "Task 2 - Second task",
                "state": "open",
                "merged": false,
                "head": ["ref": "claude-chain-my-project-2"],
                "labels": [["name": "claude-chain"]]
            ],
            [
                "number": 103,
                "title": "Task 3 - Third task",
                "state": "open",
                "merged": false,
                "head": ["ref": "claude-chain-my-project-3"],
                "labels": [["name": "claude-chain"]]
            ]
        ]
    }
    
    /// Sample prompt template with placeholders
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
    
    // MARK: - Environment Setup
    
    /// Set up GitHub Actions environment variables for testing
    public static func setupGitHubEnv() -> [String: String] {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("github-test-\(UUID().uuidString)")
        
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let outputFile = tempDir.appendingPathComponent("github_output.txt")
        let summaryFile = tempDir.appendingPathComponent("github_summary.txt")
        
        try! "".write(to: outputFile, atomically: true, encoding: .utf8)
        try! "".write(to: summaryFile, atomically: true, encoding: .utf8)
        
        return [
            "GITHUB_OUTPUT": outputFile.path,
            "GITHUB_STEP_SUMMARY": summaryFile.path,
            "GITHUB_REPOSITORY": "owner/repo",
            "GITHUB_RUN_ID": "123456789",
            "GITHUB_SERVER_URL": "https://github.com",
            "GITHUB_WORKSPACE": tempDir.path
        ]
    }
    
    // MARK: - Cleanup
    
    /// Clean up temporary directories created during tests
    public static func cleanup(directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// XCTestCase extension for common test utilities
public extension XCTestCase {
    
    /// Create a temporary directory for the test
    func createTempDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString)")
        
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Clean up after test
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        return tempDir
    }
    
    /// Assert that two URLs point to the same file
    func XCTAssertEqualPaths(_ path1: URL, _ path2: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(path1.standardizedFileURL, path2.standardizedFileURL, file: file, line: line)
    }
    
    /// Assert that file exists
    func XCTAssertFileExists(_ path: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path), 
                     "File should exist at path: \(path.path)", file: file, line: line)
    }
    
    /// Assert that file does not exist
    func XCTAssertFileNotExists(_ path: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path), 
                      "File should not exist at path: \(path.path)", file: file, line: line)
    }
    
    /// Assert that file contents equal expected string
    func XCTAssertFileContents(_ path: URL, equals expected: String, file: StaticString = #filePath, line: UInt = #line) {
        guard FileManager.default.fileExists(atPath: path.path) else {
            XCTFail("File does not exist at path: \(path.path)", file: file, line: line)
            return
        }
        
        do {
            let contents = try String(contentsOf: path, encoding: .utf8)
            XCTAssertEqual(contents, expected, file: file, line: line)
        } catch {
            XCTFail("Failed to read file contents: \(error)", file: file, line: line)
        }
    }
}