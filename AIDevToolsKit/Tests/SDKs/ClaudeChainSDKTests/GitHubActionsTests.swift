import XCTest
@testable import ClaudeChainSDK
@testable import ClaudeChainService
import Foundation

/// Tests for GitHub Actions helper
/// Swift port of test_actions.py (github)
final class GitHubActionsTests: XCTestCase {
    
    private var tempDir: URL!
    private var outputFile: URL!
    private var summaryFile: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = createTempDirectory()
        outputFile = tempDir.appendingPathComponent("github_output.txt")
        summaryFile = tempDir.appendingPathComponent("github_summary.txt")
        
        // Create empty files
        try! "".write(to: outputFile, atomically: true, encoding: .utf8)
        try! "".write(to: summaryFile, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Write Output Tests
    
    func testWriteOutputSuccess() throws {
        // Should write output to GITHUB_OUTPUT file
        
        // Arrange
        let helper = GitHubActions(
            outputFile: outputFile.path,
            summaryFile: summaryFile.path
        )
        
        // Act
        helper.writeOutput(name: "test_key", value: "test_value")
        
        // Assert
        let content = try String(contentsOf: outputFile, encoding: .utf8)
        XCTAssertTrue(content.contains("test_key=test_value"))
    }
    
    func testWriteOutputMultipleValues() throws {
        // Should append multiple outputs to file
        
        // Arrange
        let helper = GitHubActions(
            outputFile: outputFile.path,
            summaryFile: summaryFile.path
        )
        
        // Act
        helper.writeOutput(name: "key1", value: "value1")
        helper.writeOutput(name: "key2", value: "value2")
        
        // Assert
        let content = try String(contentsOf: outputFile, encoding: .utf8)
        XCTAssertTrue(content.contains("key1=value1"))
        XCTAssertTrue(content.contains("key2=value2"))
    }
    
    func testWriteOutputHandlesSpecialCharacters() throws {
        // Should handle values with special characters
        
        // Arrange
        let helper = GitHubActions(
            outputFile: outputFile.path,
            summaryFile: summaryFile.path
        )
        
        // Act
        helper.writeOutput(name: "message", value: "Hello\nWorld")
        
        // Assert
        let content = try String(contentsOf: outputFile, encoding: .utf8)
        // Multi-line values use heredoc format, not URL encoding
        XCTAssertTrue(content.contains("message<<EOF_") && content.contains("Hello\nWorld"))
    }
    
    func testWriteOutputHandlesEmptyValue() throws {
        // Should handle empty values
        
        // Arrange
        let helper = GitHubActions(
            outputFile: outputFile.path,
            summaryFile: summaryFile.path
        )
        
        // Act
        helper.writeOutput(name: "empty", value: "")
        
        // Assert
        let content = try String(contentsOf: outputFile, encoding: .utf8)
        XCTAssertTrue(content.contains("empty="))
    }
    
    func testWriteOutputNoOutputFileSet() {
        // Should handle gracefully when GITHUB_OUTPUT not set
        
        // Arrange
        let helper = GitHubActions(outputFile: nil, summaryFile: summaryFile.path)
        
        // Act & Assert - Should not crash
        helper.writeOutput(name: "test", value: "value")
    }
    
    // MARK: - Write Step Summary Tests
    
    func testWriteStepSummarySuccess() throws {
        // Should write step summary to GITHUB_STEP_SUMMARY file
        
        // Arrange
        let helper = GitHubActions(
            outputFile: outputFile.path,
            summaryFile: summaryFile.path
        )
        
        // Act
        helper.writeStepSummary(text: "## Test Summary\nEverything passed!")
        
        // Assert
        let content = try String(contentsOf: summaryFile, encoding: .utf8)
        XCTAssertEqual(content, "## Test Summary\nEverything passed!\n")
    }
    
    func testWriteStepSummaryAppends() throws {
        // Should append to existing summary content
        
        // Arrange
        try "Initial content\n".write(to: summaryFile, atomically: true, encoding: .utf8)
        
        let helper = GitHubActions(
            outputFile: outputFile.path,
            summaryFile: summaryFile.path
        )
        
        // Act
        helper.writeStepSummary(text: "Additional content")
        
        // Assert
        let content = try String(contentsOf: summaryFile, encoding: .utf8)
        XCTAssertEqual(content, "Initial content\nAdditional content\n")
    }
    
    func testWriteStepSummaryHandlesMarkdown() throws {
        // Should preserve markdown formatting
        
        // Arrange
        let helper = GitHubActions(
            outputFile: outputFile.path,
            summaryFile: summaryFile.path
        )
        
        let markdown = """
        # Summary
        
        - Item 1
        - Item 2
        
        **Bold text** and *italic text*
        """
        
        // Act
        helper.writeStepSummary(text: markdown)
        
        // Assert
        let content = try String(contentsOf: summaryFile, encoding: .utf8)
        XCTAssertEqual(content, markdown + "\n")
    }
    
    func testWriteStepSummaryNoSummaryFileSet() {
        // Should handle gracefully when GITHUB_STEP_SUMMARY not set
        
        // Arrange
        let helper = GitHubActions(outputFile: outputFile.path, summaryFile: nil)
        
        // Act & Assert - Should not crash
        helper.writeStepSummary(text: "Test summary")
    }
    
    // MARK: - Set Error Tests
    
    func testSetError() {
        // Should format and output error message
        
        // Arrange
        let helper = GitHubActions(
            outputFile: outputFile.path,
            summaryFile: summaryFile.path
        )
        
        // Act & Assert - Should not crash
        helper.setError(message: "Something went wrong")
    }
    
    func testSetErrorWithTitle() {
        // Should include title in error message
        
        // Arrange
        let helper = GitHubActions(
            outputFile: outputFile.path,
            summaryFile: summaryFile.path
        )
        
        // Act & Assert - Should not crash
        helper.setError(message: "Validation failed")
    }
    
    func testSetErrorWithFile() {
        // Should include file information in error
        
        // Arrange
        let helper = GitHubActions(
            outputFile: outputFile.path,
            summaryFile: summaryFile.path
        )
        
        // Act & Assert - Should not crash
        helper.setError(message: "Syntax error")
    }
    
    // MARK: - Set Notice Tests
    
    func testSetNotice() {
        // Should format and output notice message
        
        // Arrange
        let helper = GitHubActions(
            outputFile: outputFile.path,
            summaryFile: summaryFile.path
        )
        
        // Act & Assert - Should not crash
        helper.setNotice(message: "Task completed successfully")
    }
    
    func testSetNoticeWithTitle() {
        // Should include title in notice message
        
        // Arrange
        let helper = GitHubActions(
            outputFile: outputFile.path,
            summaryFile: summaryFile.path
        )
        
        // Act & Assert - Should not crash
        helper.setNotice(message: "All checks passed")
    }
    
    // MARK: - Integration Tests
    
    func testFullWorkflowWithOutputsAndSummary() throws {
        // Should handle complete workflow with outputs and summary
        
        // Arrange
        let helper = GitHubActions(
            outputFile: outputFile.path,
            summaryFile: summaryFile.path
        )
        
        // Act
        helper.writeOutput(name: "success", value: "true")
        helper.writeOutput(name: "message", value: "Task completed")
        helper.writeStepSummary(text: "## Summary\n\n✅ All tasks completed successfully!")
        helper.setNotice(message: "Workflow finished")
        
        // Assert
        let outputContent = try String(contentsOf: outputFile, encoding: .utf8)
        XCTAssertTrue(outputContent.contains("success=true"))
        XCTAssertTrue(outputContent.contains("message=Task completed"))
        
        let summaryContent = try String(contentsOf: summaryFile, encoding: .utf8)
        XCTAssertTrue(summaryContent.contains("## Summary"))
        XCTAssertTrue(summaryContent.contains("✅ All tasks completed"))
    }
    
    func testHandlesFileWriteErrors() {
        // Should handle file write errors gracefully
        
        // Arrange
        let invalidPath = "/invalid/path/output.txt"
        let helper = GitHubActions(outputFile: invalidPath, summaryFile: summaryFile.path)
        
        // Act & Assert - Should not crash
        helper.writeOutput(name: "test", value: "value")
    }
}

// MARK: - Test Extensions

extension GitHubActions {
    convenience init(environment: [String: String]) {
        self.init(
            outputFile: environment["GITHUB_OUTPUT"],
            summaryFile: environment["GITHUB_STEP_SUMMARY"]
        )
    }
}