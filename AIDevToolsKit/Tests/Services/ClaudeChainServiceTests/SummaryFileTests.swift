/// Unit tests for SummaryFile domain model
import XCTest
import Foundation
@testable import ClaudeChainService

class SummaryFileTests: XCTestCase {
    
    // MARK: - SummaryFile Construction Tests
    
    func testCanCreateSummaryFileWithContent() throws {
        // Should be able to create SummaryFile with content
        // Act
        let summary = SummaryFile(content: "This is a summary")
        
        // Assert
        XCTAssertEqual(summary.content, "This is a summary")
    }
    
    func testCanCreateSummaryFileWithNoneContent() throws {
        // Should be able to create SummaryFile with None content
        // Act
        let summary = SummaryFile(content: nil)
        
        // Assert
        XCTAssertNil(summary.content)
    }
    
    func testHasContentPropertyWithContent() throws {
        // Should return True when content exists
        // Arrange
        let summary = SummaryFile(content: "Some content")
        
        // Act
        let hasContent = summary.hasContent
        
        // Assert
        XCTAssertTrue(hasContent)
    }
    
    func testHasContentPropertyWithNone() throws {
        // Should return False when content is None
        // Arrange
        let summary = SummaryFile(content: nil)
        
        // Act
        let hasContent = summary.hasContent
        
        // Assert
        XCTAssertFalse(hasContent)
    }
    
    func testHasContentPropertyWithEmptyString() throws {
        // Should return False when content is empty string
        // Arrange
        let summary = SummaryFile(content: "")
        
        // Act
        let hasContent = summary.hasContent
        
        // Assert
        XCTAssertFalse(hasContent)
    }
    
    func testHasContentPropertyWithWhitespace() throws {
        // Should return False when content is only whitespace
        // Arrange
        let summary = SummaryFile(content: "   \n\t  ")
        
        // Act
        let hasContent = summary.hasContent
        
        // Assert
        XCTAssertFalse(hasContent)
    }
    
    // MARK: - SummaryFile.fromFile() Tests
    
    func testFromFileWithValidContent() throws {
        // Should read content from valid file
        // Arrange
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".md")
        let content = "# PR Summary\n\nThis is the content."
        try content.write(to: tempFile, atomically: true, encoding: .utf8)
        
        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }
        
        // Act
        let summary = SummaryFile.fromFile(tempFile.path)
        
        // Assert
        XCTAssertEqual(summary.content, "# PR Summary\n\nThis is the content.")
        XCTAssertTrue(summary.hasContent)
    }
    
    func testFromFileStripsWhitespace() throws {
        // Should strip leading and trailing whitespace
        // Arrange
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".md")
        let content = "\n\n  Content here  \n\n"
        try content.write(to: tempFile, atomically: true, encoding: .utf8)
        
        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }
        
        // Act
        let summary = SummaryFile.fromFile(tempFile.path)
        
        // Assert
        XCTAssertEqual(summary.content, "Content here")
        XCTAssertTrue(summary.hasContent)
    }
    
    func testFromFileWithEmptyFile() throws {
        // Should return None content for empty file
        // Arrange
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".md")
        try "".write(to: tempFile, atomically: true, encoding: .utf8)
        
        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }
        
        // Act
        let summary = SummaryFile.fromFile(tempFile.path)
        
        // Assert
        XCTAssertNil(summary.content)
        XCTAssertFalse(summary.hasContent)
    }
    
    func testFromFileWithWhitespaceOnlyFile() throws {
        // Should return None content for file with only whitespace
        // Arrange
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".md")
        let content = "   \n\t\n   "
        try content.write(to: tempFile, atomically: true, encoding: .utf8)
        
        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }
        
        // Act
        let summary = SummaryFile.fromFile(tempFile.path)
        
        // Assert
        XCTAssertNil(summary.content)
        XCTAssertFalse(summary.hasContent)
    }
    
    func testFromFileWithNonexistentFile() throws {
        // Should return None content for nonexistent file
        // Act
        let summary = SummaryFile.fromFile("/nonexistent/file.md")
        
        // Assert
        XCTAssertNil(summary.content)
        XCTAssertFalse(summary.hasContent)
    }
    
    func testFromFileWithEmptyPath() throws {
        // Should return None content for empty path
        // Act
        let summary = SummaryFile.fromFile("")
        
        // Assert
        XCTAssertNil(summary.content)
        XCTAssertFalse(summary.hasContent)
    }
    
    func testFromFileWithMultilineContent() throws {
        // Should preserve multiline content
        // Arrange
        let content = """
# Summary

## Changes
- Change 1
- Change 2

## Impact
This affects the system.
"""
        
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".md")
        try content.write(to: tempFile, atomically: true, encoding: .utf8)
        
        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }
        
        // Act
        let summary = SummaryFile.fromFile(tempFile.path)
        
        // Assert
        XCTAssertEqual(summary.content, content)
        XCTAssertTrue(summary.hasContent)
    }
    
    func testFromFileHandlesReadErrorGracefully() throws {
        // Should return None content on read error
        // Arrange - Create a directory, not a file (will cause read error)
        let tempDir = FileManager.default.temporaryDirectory
        let invalidPath = tempDir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: invalidPath, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: invalidPath)
        }
        
        // Act
        let summary = SummaryFile.fromFile(invalidPath.path)
        
        // Assert
        XCTAssertNil(summary.content)
        XCTAssertFalse(summary.hasContent)
    }
}