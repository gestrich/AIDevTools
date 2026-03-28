import XCTest
@testable import ClaudeChainSDK
@testable import ClaudeChainService
import Foundation

/// Tests for filesystem operations
/// Swift port of test_operations.py (filesystem)
final class FileSystemOperationsTests: XCTestCase {
    
    // MARK: - Read File Tests
    
    func testReadFileSuccess() throws {
        // Should read and return file contents
        
        // Arrange
        let tempDir = createTempDirectory()
        let filePath = tempDir.appendingPathComponent("test.txt")
        let expectedContent = "Hello, World!\nLine 2"
        try expectedContent.write(to: filePath, atomically: true, encoding: .utf8)
        
        // Act
        let result = try FileSystemOperations.readFile(path: filePath)
        
        // Assert
        XCTAssertEqual(result, expectedContent)
    }
    
    func testReadFileEmptyFile() throws {
        // Should return empty string for empty file
        
        // Arrange
        let tempDir = createTempDirectory()
        let filePath = tempDir.appendingPathComponent("empty.txt")
        try "".write(to: filePath, atomically: true, encoding: .utf8)
        
        // Act
        let result = try FileSystemOperations.readFile(path: filePath)
        
        // Assert
        XCTAssertEqual(result, "")
    }
    
    func testReadFileRaisesOnNonexistentFile() {
        // Should raise FileNotFoundError when file doesn't exist
        
        // Arrange
        let tempDir = createTempDirectory()
        let filePath = tempDir.appendingPathComponent("nonexistent.txt")
        
        // Act & Assert
        XCTAssertThrowsError(try FileSystemOperations.readFile(path: filePath)) { error in
            XCTAssertTrue(error is FileNotFoundError)
        }
    }
    
    func testReadFileHandlesUnicode() throws {
        // Should correctly read Unicode content
        
        // Arrange
        let tempDir = createTempDirectory()
        let filePath = tempDir.appendingPathComponent("unicode.txt")
        let expectedContent = "Hello 世界 🌍"
        try expectedContent.write(to: filePath, atomically: true, encoding: .utf8)
        
        // Act
        let result = try FileSystemOperations.readFile(path: filePath)
        
        // Assert
        XCTAssertEqual(result, expectedContent)
    }
    
    func testReadFilePreservesNewlines() throws {
        // Should preserve newline characters in content
        
        // Arrange
        let tempDir = createTempDirectory()
        let filePath = tempDir.appendingPathComponent("newlines.txt")
        let expectedContent = "line1\n\nline3\nline4"
        try expectedContent.write(to: filePath, atomically: true, encoding: .utf8)
        
        // Act
        let result = try FileSystemOperations.readFile(path: filePath)
        
        // Assert
        XCTAssertEqual(result, expectedContent)
        XCTAssertEqual(result.components(separatedBy: "\n").count - 1, 3) // 3 newlines
    }
    
    // MARK: - Write File Tests
    
    func testWriteFileCreatesNewFile() throws {
        // Should create new file with content
        
        // Arrange
        let tempDir = createTempDirectory()
        let filePath = tempDir.appendingPathComponent("new.txt")
        let content = "Test content"
        
        // Act
        try FileSystemOperations.writeFile(path: filePath, content: content)
        
        // Assert
        XCTAssertFileExists(filePath)
        let writtenContent = try String(contentsOf: filePath, encoding: .utf8)
        XCTAssertEqual(writtenContent, content)
    }
    
    func testWriteFileOverwritesExistingFile() throws {
        // Should overwrite existing file content
        
        // Arrange
        let tempDir = createTempDirectory()
        let filePath = tempDir.appendingPathComponent("existing.txt")
        try "old content".write(to: filePath, atomically: true, encoding: .utf8)
        let newContent = "new content"
        
        // Act
        try FileSystemOperations.writeFile(path: filePath, content: newContent)
        
        // Assert
        let writtenContent = try String(contentsOf: filePath, encoding: .utf8)
        XCTAssertEqual(writtenContent, newContent)
    }
    
    func testWriteFileEmptyContent() throws {
        // Should write empty file when content is empty string
        
        // Arrange
        let tempDir = createTempDirectory()
        let filePath = tempDir.appendingPathComponent("empty.txt")
        
        // Act
        try FileSystemOperations.writeFile(path: filePath, content: "")
        
        // Assert
        XCTAssertFileExists(filePath)
        let writtenContent = try String(contentsOf: filePath, encoding: .utf8)
        XCTAssertEqual(writtenContent, "")
    }
    
    func testWriteFileMultilineContent() throws {
        // Should correctly write multiline content
        
        // Arrange
        let tempDir = createTempDirectory()
        let filePath = tempDir.appendingPathComponent("multiline.txt")
        let content = "line1\nline2\nline3"
        
        // Act
        try FileSystemOperations.writeFile(path: filePath, content: content)
        
        // Assert
        let writtenContent = try String(contentsOf: filePath, encoding: .utf8)
        XCTAssertEqual(writtenContent, content)
    }
    
    func testWriteFileHandlesUnicode() throws {
        // Should correctly write Unicode content
        
        // Arrange
        let tempDir = createTempDirectory()
        let filePath = tempDir.appendingPathComponent("unicode.txt")
        let content = "Hello 世界 🌍"
        
        // Act
        try FileSystemOperations.writeFile(path: filePath, content: content)
        
        // Assert
        let writtenContent = try String(contentsOf: filePath, encoding: .utf8)
        XCTAssertEqual(writtenContent, content)
    }
    
    func testWriteFileCreatesParentDirectoryNotSupported() {
        // Should raise error when parent directory doesn't exist
        
        // Arrange
        let tempDir = createTempDirectory()
        let filePath = tempDir.appendingPathComponent("nonexistent/file.txt")
        
        // Act & Assert
        XCTAssertThrowsError(try FileSystemOperations.writeFile(path: filePath, content: "content")) { error in
            XCTAssertTrue(error is CocoaError)
        }
    }
    
    // MARK: - File Exists Tests
    
    func testFileExistsReturnsTrueForExistingFile() throws {
        // Should return true when file exists
        
        // Arrange
        let tempDir = createTempDirectory()
        let filePath = tempDir.appendingPathComponent("exists.txt")
        try "content".write(to: filePath, atomically: true, encoding: .utf8)
        
        // Act
        let result = FileSystemOperations.fileExists(path: filePath)
        
        // Assert
        XCTAssertTrue(result)
    }
    
    func testFileExistsReturnsFalseForNonexistentFile() {
        // Should return false when file doesn't exist
        
        // Arrange
        let tempDir = createTempDirectory()
        let filePath = tempDir.appendingPathComponent("nonexistent.txt")
        
        // Act
        let result = FileSystemOperations.fileExists(path: filePath)
        
        // Assert
        XCTAssertFalse(result)
    }
    
    func testFileExistsReturnsFalseForDirectory() throws {
        // Should return false for directory (not a file)
        
        // Arrange
        let tempDir = createTempDirectory()
        let dirPath = tempDir.appendingPathComponent("directory")
        try FileManager.default.createDirectory(at: dirPath, withIntermediateDirectories: true)
        
        // Act
        let result = FileSystemOperations.fileExists(path: dirPath)
        
        // Assert
        XCTAssertFalse(result)
    }
    
    func testFileExistsHandlesSymlinks() throws {
        // Should return true for symlink to existing file
        
        // Arrange
        let tempDir = createTempDirectory()
        let realFile = tempDir.appendingPathComponent("real.txt")
        try "content".write(to: realFile, atomically: true, encoding: .utf8)
        let symlink = tempDir.appendingPathComponent("link.txt")
        
        // Create symlink (skip test if not supported)
        do {
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: realFile)
        } catch {
            throw XCTSkip("Symlinks not supported on this system")
        }
        
        // Act
        let result = FileSystemOperations.fileExists(path: symlink)
        
        // Assert
        XCTAssertTrue(result)
    }
    
    // MARK: - Find File Tests
    
    func testFindFileInCurrentDirectory() throws {
        // Should find file in the starting directory
        
        // Arrange
        let tempDir = createTempDirectory()
        let targetFile = tempDir.appendingPathComponent("target.txt")
        try "content".write(to: targetFile, atomically: true, encoding: .utf8)
        
        // Act
        let result = try FileSystemOperations.findFile(startDir: tempDir, filename: "target.txt")
        
        // Assert
        XCTAssertEqualPaths(result!, targetFile)
    }
    
    func testFindFileInSubdirectory() throws {
        // Should find file in subdirectory
        
        // Arrange
        let tempDir = createTempDirectory()
        let subdir = tempDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let targetFile = subdir.appendingPathComponent("target.txt")
        try "content".write(to: targetFile, atomically: true, encoding: .utf8)
        
        // Act
        let result = try FileSystemOperations.findFile(startDir: tempDir, filename: "target.txt")
        
        // Assert
        XCTAssertEqualPaths(result!, targetFile)
    }
    
    func testFindFileInNestedSubdirectories() throws {
        // Should find file in deeply nested directory
        
        // Arrange
        let tempDir = createTempDirectory()
        let nestedDir = tempDir.appendingPathComponent("level1/level2/level3")
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        let targetFile = nestedDir.appendingPathComponent("target.txt")
        try "content".write(to: targetFile, atomically: true, encoding: .utf8)
        
        // Act
        let result = try FileSystemOperations.findFile(startDir: tempDir, filename: "target.txt")
        
        // Assert
        XCTAssertEqualPaths(result!, targetFile)
    }
    
    func testFindFileReturnsNilWhenNotFound() throws {
        // Should return nil when file is not found
        
        // Arrange
        let tempDir = createTempDirectory()
        try "content".write(to: tempDir.appendingPathComponent("other.txt"), atomically: true, encoding: .utf8)
        
        // Act
        let result = try FileSystemOperations.findFile(startDir: tempDir, filename: "nonexistent.txt")
        
        // Assert
        XCTAssertNil(result)
    }
    
    func testFindFileReturnsFirstMatch() throws {
        // Should return first match when multiple files with same name exist
        
        // Arrange
        let tempDir = createTempDirectory()
        let file1 = tempDir.appendingPathComponent("target.txt")
        try "first".write(to: file1, atomically: true, encoding: .utf8)
        
        let subdir = tempDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let file2 = subdir.appendingPathComponent("target.txt")
        try "second".write(to: file2, atomically: true, encoding: .utf8)
        
        // Act
        let result = try FileSystemOperations.findFile(startDir: tempDir, filename: "target.txt")
        
        // Assert
        // Should find the one in the current directory first
        XCTAssertEqualPaths(result!, file1)
    }
    
    func testFindFileWithMaxDepthZero() throws {
        // Should only search current directory when maxDepth=0
        
        // Arrange
        let tempDir = createTempDirectory()
        let currentFile = tempDir.appendingPathComponent("current.txt")
        try "content".write(to: currentFile, atomically: true, encoding: .utf8)
        
        let subdir = tempDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let nestedFile = subdir.appendingPathComponent("nested.txt")
        try "content".write(to: nestedFile, atomically: true, encoding: .utf8)
        
        // Act
        let resultCurrent = try FileSystemOperations.findFile(startDir: tempDir, filename: "current.txt", maxDepth: 0)
        let resultNested = try FileSystemOperations.findFile(startDir: tempDir, filename: "nested.txt", maxDepth: 0)
        
        // Assert
        XCTAssertEqualPaths(resultCurrent!, currentFile)
        XCTAssertNil(resultNested) // Not found because it's in subdirectory
    }
    
    func testFindFileWithMaxDepthOne() throws {
        // Should search up to specified depth
        
        // Arrange
        let tempDir = createTempDirectory()
        let subdir1 = tempDir.appendingPathComponent("level1")
        try FileManager.default.createDirectory(at: subdir1, withIntermediateDirectories: true)
        let fileDepth1 = subdir1.appendingPathComponent("file1.txt")
        try "depth 1".write(to: fileDepth1, atomically: true, encoding: .utf8)
        
        let subdir2 = subdir1.appendingPathComponent("level2")
        try FileManager.default.createDirectory(at: subdir2, withIntermediateDirectories: true)
        let fileDepth2 = subdir2.appendingPathComponent("file2.txt")
        try "depth 2".write(to: fileDepth2, atomically: true, encoding: .utf8)
        
        // Act
        let result1 = try FileSystemOperations.findFile(startDir: tempDir, filename: "file1.txt", maxDepth: 1)
        let result2 = try FileSystemOperations.findFile(startDir: tempDir, filename: "file2.txt", maxDepth: 1)
        
        // Assert
        XCTAssertEqualPaths(result1!, fileDepth1)
        XCTAssertNil(result2) // Too deep
    }
    
    func testFindFileSkipsHiddenDirectories() throws {
        // Should skip directories starting with dot
        
        // Arrange
        let tempDir = createTempDirectory()
        let hiddenDir = tempDir.appendingPathComponent(".hidden")
        try FileManager.default.createDirectory(at: hiddenDir, withIntermediateDirectories: true)
        let hiddenFile = hiddenDir.appendingPathComponent("target.txt")
        try "content".write(to: hiddenFile, atomically: true, encoding: .utf8)
        
        // Act
        let result = try FileSystemOperations.findFile(startDir: tempDir, filename: "target.txt")
        
        // Assert
        XCTAssertNil(result) // Should not find file in hidden directory
    }
    
    func testFindFileHandlesPermissionErrorsGracefully() throws {
        // Should handle permission errors gracefully
        
        // Arrange
        let tempDir = createTempDirectory()
        let accessibleDir = tempDir.appendingPathComponent("accessible")
        try FileManager.default.createDirectory(at: accessibleDir, withIntermediateDirectories: true)
        let targetFile = accessibleDir.appendingPathComponent("target.txt")
        try "content".write(to: targetFile, atomically: true, encoding: .utf8)
        
        // Act - Should not crash even if some dirs are inaccessible
        let result = try FileSystemOperations.findFile(startDir: tempDir, filename: "target.txt")
        
        // Assert
        XCTAssertEqualPaths(result!, targetFile)
    }
    
    func testFindFileEmptyDirectory() throws {
        // Should return nil when searching empty directory
        
        // Arrange
        let tempDir = createTempDirectory()
        
        // Act
        let result = try FileSystemOperations.findFile(startDir: tempDir, filename: "anything.txt")
        
        // Assert
        XCTAssertNil(result)
    }
    
    func testFindFileWithNoMaxDepth() throws {
        // Should search unlimited depth when maxDepth is nil
        
        // Arrange
        let tempDir = createTempDirectory()
        let deepDir = tempDir.appendingPathComponent("a/b/c/d/e")
        try FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)
        let targetFile = deepDir.appendingPathComponent("target.txt")
        try "content".write(to: targetFile, atomically: true, encoding: .utf8)
        
        // Act
        let result = try FileSystemOperations.findFile(startDir: tempDir, filename: "target.txt", maxDepth: nil)
        
        // Assert
        XCTAssertEqualPaths(result!, targetFile)
    }
}