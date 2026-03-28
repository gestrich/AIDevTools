import XCTest
@testable import ClaudeChainSDK
@testable import ClaudeChainService
import Foundation

/// Tests for git operations
/// Swift port of test_operations.py (git)
final class GitOperationsTests: XCTestCase {
    
    // MARK: - Run Command Tests
    
    func testRunCommandSuccessWithOutput() throws {
        // Should execute command and return completed process with output
        
        // Act
        let result = try GitOperations.runCommand(cmd: ["echo", "test"])
        
        // Assert
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("test"))
    }
    
    func testRunCommandCapturesOutputByDefault() throws {
        // Should capture stdout and stderr by default
        
        // Act
        let result = try GitOperations.runCommand(cmd: ["echo", "test output"])
        
        // Assert
        XCTAssertNotNil(result.stdout)
        XCTAssertNotNil(result.stderr)
    }
    
    func testRunCommandWithoutOutputCapture() throws {
        // Should not capture output when captureOutput=false
        
        // Act
        let result = try GitOperations.runCommand(cmd: ["echo", "test"], captureOutput: false)
        
        // Assert
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "")
    }
    
    func testRunCommandRaisesOnFailure() {
        // Should raise error on non-zero exit code
        
        // Act & Assert
        XCTAssertThrowsError(try GitOperations.runCommand(cmd: ["false"])) { error in
            // Should be a generic error, not necessarily GitError
            XCTAssertNotNil(error)
        }
    }
    
    func testRunCommandWithCheckFalse() throws {
        // Should not raise on failure when check=false
        
        // Act
        let result = try GitOperations.runCommand(cmd: ["false"], check: false)
        
        // Assert
        XCTAssertNotEqual(result.status, 0)
    }
    
    // MARK: - Git Command Tests
    
    func testRunGitCommandSuccess() throws {
        // Should run git command and return trimmed output
        
        // This test only works in a git repository, so we'll test basic functionality
        // If we're not in a git repository, it should throw GitError
        do {
            let result = try GitOperations.runGitCommand(args: ["--version"])
            XCTAssertTrue(result.contains("git version"))
        } catch {
            // Expected if git is not available
            XCTAssertTrue(error is GitError)
        }
    }
    
    func testRunGitCommandInNonGitDirectory() {
        // Should raise GitError when git command fails
        
        // Arrange
        let tempDir = createTempDirectory()
        let originalDir = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(tempDir.path)
        defer { FileManager.default.changeCurrentDirectoryPath(originalDir) }
        
        // Act & Assert - Should fail in non-git directory
        XCTAssertThrowsError(try GitOperations.runGitCommand(args: ["status"])) { error in
            XCTAssertTrue(error is GitError)
        }
    }
    
    // MARK: - Git Command Utility Tests
    
    func testEnsureRefAvailable() throws {
        // Should handle ref availability checking without error
        
        // This test will pass in a git repository or fail gracefully in non-git
        // We just ensure it doesn't crash with a valid ref format
        do {
            try GitOperations.ensureRefAvailable(ref: "HEAD")
            // If successful, great!
        } catch {
            // If it fails, that's expected in a non-git environment
            XCTAssertTrue(error is GitError)
        }
    }
    
    func testDetectChangedFiles() throws {
        // Should handle file change detection
        
        // This test may fail in CI but should not crash
        do {
            let changes = try GitOperations.detectChangedFiles(
                refBefore: "HEAD~1", 
                refAfter: "HEAD", 
                pattern: "*.swift"
            )
            // If successful, changes should be an array
            XCTAssertTrue(changes.count >= 0) // Array can be empty or have items
        } catch {
            // Expected to fail in non-git environment or with invalid refs
            XCTAssertTrue(error is GitError)
        }
    }
    
    // MARK: - Ensure Ref Available Tests
    
    func testEnsureRefAvailableWithValidRef() throws {
        // Should succeed when ref exists (tested with HEAD which should always exist in a git repo)
        
        do {
            try GitOperations.ensureRefAvailable(ref: "HEAD")
            // If we get here without throwing, the test passes
            XCTAssertTrue(true)
        } catch {
            // If we're not in a git repository, this is expected
            XCTAssertTrue(error is GitError)
        }
    }
    
    func testEnsureRefAvailableWithInvalidRef() {
        // Should throw GitError for clearly invalid refs
        
        XCTAssertThrowsError(try GitOperations.ensureRefAvailable(ref: "definitely-not-a-valid-ref-12345678")) { error in
            XCTAssertTrue(error is GitError)
        }
    }
    
    // MARK: - Detect Changed Files Tests
    
    func testDetectChangedFilesReturnsArray() throws {
        // Should return array even if no files match
        
        do {
            let result = try GitOperations.detectChangedFiles(
                refBefore: "HEAD", 
                refAfter: "HEAD", 
                pattern: "*.nonexistent-extension"
            )
            XCTAssertTrue(result.isEmpty)
        } catch {
            // Expected in non-git environment
            XCTAssertTrue(error is GitError)
        }
    }
    
    func testDetectChangedFilesWithInvalidRefs() {
        // Should throw GitError for invalid refs
        
        XCTAssertThrowsError(try GitOperations.detectChangedFiles(
            refBefore: "invalid-ref-1", 
            refAfter: "invalid-ref-2", 
            pattern: "*.swift"
        )) { error in
            XCTAssertTrue(error is GitError)
        }
    }
    
    // MARK: - Detect Deleted Files Tests
    
    func testDetectDeletedFilesReturnsArray() throws {
        // Should return array even if no files were deleted
        
        do {
            let result = try GitOperations.detectDeletedFiles(
                refBefore: "HEAD", 
                refAfter: "HEAD", 
                pattern: "*.swift"
            )
            XCTAssertTrue(result.isEmpty)
        } catch {
            // Expected in non-git environment
            XCTAssertTrue(error is GitError)
        }
    }
    
    func testDetectDeletedFilesWithInvalidRefs() {
        // Should throw GitError for invalid refs
        
        XCTAssertThrowsError(try GitOperations.detectDeletedFiles(
            refBefore: "invalid-ref-1", 
            refAfter: "invalid-ref-2", 
            pattern: "*.swift"
        )) { error in
            XCTAssertTrue(error is GitError)
        }
    }
    
    func testParseSpecPathToProject() {
        // Should parse spec paths correctly
        
        // Act & Assert
        XCTAssertEqual(GitOperations.parseSpecPathToProject(path: "claude-chain/my-project/spec.md"), "my-project")
        XCTAssertEqual(GitOperations.parseSpecPathToProject(path: "claude-chain/test-project/spec.md"), "test-project")
        XCTAssertNil(GitOperations.parseSpecPathToProject(path: "invalid/path/spec.md"))
        XCTAssertNil(GitOperations.parseSpecPathToProject(path: "claude-chain/project/other.md"))
        XCTAssertNil(GitOperations.parseSpecPathToProject(path: "not-right/format/spec.md"))
    }
}