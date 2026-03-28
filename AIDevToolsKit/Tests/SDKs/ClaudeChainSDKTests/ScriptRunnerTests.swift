import XCTest
@testable import ClaudeChainSDK
@testable import ClaudeChainService
import Foundation

/// Unit tests for action script runner
/// Swift port of test_script_runner.py
final class ScriptRunnerTests: XCTestCase {
    
    // MARK: - Run Action Script Tests
    
    func testScriptNotFoundReturnsSuccess() throws {
        // Script doesn't exist → returns success (optional)
        
        // Arrange
        let tempDir = createTempDirectory()
        let projectPath = tempDir.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)
        
        // Act
        let result = try ScriptRunner.runActionScript(
            projectPath: projectPath.path,
            scriptType: "pre",
            workingDirectory: tempDir.path
        )
        
        // Assert
        XCTAssertTrue(result.success)
        XCTAssertFalse(result.scriptExists)
        XCTAssertNil(result.exitCode)
    }
    
    func testScriptExistsAndSucceeds() throws {
        // Script exists and succeeds → returns success with stdout
        
        // Arrange
        let tempDir = createTempDirectory()
        let projectPath = tempDir.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)
        
        let scriptPath = projectPath.appendingPathComponent("pre-action.sh")
        let scriptContent = "#!/bin/bash\necho 'Hello from pre-action'\n"
        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
        
        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        
        // Act
        let result = try ScriptRunner.runActionScript(
            projectPath: projectPath.path,
            scriptType: "pre",
            workingDirectory: tempDir.path
        )
        
        // Assert
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.scriptExists)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Hello from pre-action"))
    }
    
    func testScriptExistsAndFails() throws {
        // Script exists and fails → raises ActionScriptError
        
        // Arrange
        let tempDir = createTempDirectory()
        let projectPath = tempDir.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)
        
        let scriptPath = projectPath.appendingPathComponent("post-action.sh")
        let scriptContent = "#!/bin/bash\necho 'Error message' >&2\nexit 1\n"
        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
        
        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        
        // Act & Assert
        XCTAssertThrowsError(try ScriptRunner.runActionScript(
            projectPath: projectPath.path,
            scriptType: "post",
            workingDirectory: tempDir.path
        )) { error in
            guard let actionScriptError = error as? ActionScriptError else {
                XCTFail("Expected ActionScriptError, got \(type(of: error))")
                return
            }
            
            XCTAssertEqual(actionScriptError.exitCode, 1)
            XCTAssertTrue(actionScriptError.stderr.contains("Error message"))
        }
    }
    
    func testScriptWithNonExecutablePermissions() throws {
        // Script with non-executable permissions → makes executable and runs
        
        // Arrange
        let tempDir = createTempDirectory()
        let projectPath = tempDir.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)
        
        let scriptPath = projectPath.appendingPathComponent("pre-action.sh")
        let scriptContent = "#!/bin/bash\necho 'Made executable'\n"
        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
        
        // Create without execute permission
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: scriptPath.path)
        
        // Act
        let result = try ScriptRunner.runActionScript(
            projectPath: projectPath.path,
            scriptType: "pre",
            workingDirectory: tempDir.path
        )
        
        // Assert
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.stdout.contains("Made executable"))
    }
    
    func testScriptProducesStderr() throws {
        // Script produces stderr → captured in result
        
        // Arrange
        let tempDir = createTempDirectory()
        let projectPath = tempDir.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)
        
        let scriptPath = projectPath.appendingPathComponent("pre-action.sh")
        let scriptContent = "#!/bin/bash\necho 'stdout' && echo 'stderr' >&2\n"
        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
        
        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        
        // Act
        let result = try ScriptRunner.runActionScript(
            projectPath: projectPath.path,
            scriptType: "pre",
            workingDirectory: tempDir.path
        )
        
        // Assert
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.stdout.contains("stdout"))
        XCTAssertTrue(result.stderr.contains("stderr"))
    }
    
    func testPostActionScript() throws {
        // Post-action script runs correctly
        
        // Arrange
        let tempDir = createTempDirectory()
        let projectPath = tempDir.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)
        
        let scriptPath = projectPath.appendingPathComponent("post-action.sh")
        let scriptContent = "#!/bin/bash\necho 'Post action complete'\n"
        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
        
        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        
        // Act
        let result = try ScriptRunner.runActionScript(
            projectPath: projectPath.path,
            scriptType: "post",
            workingDirectory: tempDir.path
        )
        
        // Assert
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.stdout.contains("Post action complete"))
    }
    
    func testScriptRunsInWorkingDirectory() throws {
        // Script runs from working_directory, not project_path
        
        // Arrange
        let tempDir = createTempDirectory()
        let projectPath = tempDir.appendingPathComponent("project")
        let workDir = tempDir.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        
        let scriptPath = projectPath.appendingPathComponent("pre-action.sh")
        let scriptContent = "#!/bin/bash\npwd\n"
        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
        
        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        
        // Act
        let result = try ScriptRunner.runActionScript(
            projectPath: projectPath.path,
            scriptType: "pre",
            workingDirectory: workDir.path
        )
        
        // Assert
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.stdout.contains(workDir.path))
    }
    
    // MARK: - Ensure Executable Tests
    // Note: ensureExecutable is private, so we can't test it directly.
    // These tests are covered indirectly through the script execution tests above.
    
    // MARK: - ActionResult Tests
    
    func testActionResultScriptNotFoundFactory() {
        // Test scriptNotFound factory method
        
        // Act
        let result = ActionResult.scriptNotFound(scriptPath: "/path/to/script.sh")
        
        // Assert
        XCTAssertTrue(result.success)
        XCTAssertFalse(result.scriptExists)
        XCTAssertNil(result.exitCode)
        XCTAssertEqual(result.scriptPath, "/path/to/script.sh")
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "")
    }
    
    func testActionResultFromExecutionSuccess() {
        // Test fromExecution with successful exit code
        
        // Act
        let result = ActionResult.fromExecution(
            scriptPath: "/path/to/script.sh",
            exitCode: 0,
            stdout: "output",
            stderr: ""
        )
        
        // Assert
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.scriptExists)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "output")
    }
    
    func testActionResultFromExecutionFailure() {
        // Test fromExecution with failed exit code
        
        // Act
        let result = ActionResult.fromExecution(
            scriptPath: "/path/to/script.sh",
            exitCode: 1,
            stdout: "",
            stderr: "error"
        )
        
        // Assert
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.scriptExists)
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "error")
    }
    
    // MARK: - ActionScriptError Tests
    
    func testActionScriptErrorMessageFormat() {
        // Test error message formatting
        
        // Act
        let error = ActionScriptError(
            scriptPath: "/path/to/script.sh",
            exitCode: 1,
            stdout: "",
            stderr: "Something went wrong"
        )
        
        // Assert
        let errorMessage = error.message
        XCTAssertTrue(errorMessage.contains("script.sh"))
        XCTAssertTrue(errorMessage.contains("exit code 1"))
        XCTAssertTrue(errorMessage.contains("Something went wrong"))
    }
    
    func testActionScriptErrorWithoutStderr() {
        // Test error without stderr
        
        // Act
        let error = ActionScriptError(
            scriptPath: "/path/to/script.sh",
            exitCode: 2,
            stdout: "",
            stderr: ""
        )
        
        // Assert
        let errorMessage = error.message
        XCTAssertTrue(errorMessage.contains("exit code 2"))
        XCTAssertEqual(error.exitCode, 2)
    }
    
    func testActionScriptErrorLongStderrTruncated() {
        // Test that long stderr is truncated in message
        
        // Arrange
        let longStderr = String(repeating: "x", count: 1000)
        
        // Act
        let error = ActionScriptError(
            scriptPath: "/path/to/script.sh",
            exitCode: 1,
            stdout: "",
            stderr: longStderr
        )
        
        // Assert
        // Message should be truncated to first 500 chars of stderr
        let errorMessage = error.localizedDescription
        XCTAssertTrue(errorMessage.count < 600)
    }
}