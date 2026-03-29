/// Custom errors for ClaudeChain operations
import Foundation

/// Base error for continuous refactoring operations
public struct ContinuousRefactoringError: LocalizedError {
    public let message: String

    public var errorDescription: String? { message }

    public init(_ message: String) {
        self.message = message
    }
}

/// Configuration file issues
public struct ConfigurationError: LocalizedError {
    public let message: String

    public var errorDescription: String? { message }

    public init(_ message: String) {
        self.message = message
    }
}

/// Missing required files
public struct FileNotFoundError: LocalizedError {
    public let message: String

    public var errorDescription: String? { message }

    public init(_ message: String) {
        self.message = message
    }
}

/// Git operation failures
public struct GitError: LocalizedError {
    public let message: String

    public var errorDescription: String? { message }

    public init(_ message: String) {
        self.message = message
    }
}

/// GitHub API call failures
public struct GitHubAPIError: LocalizedError {
    public let message: String

    public var errorDescription: String? { message }

    public init(_ message: String) {
        self.message = message
    }
}

/// Action script execution failures
public struct ActionScriptError: Error {
    public let scriptPath: String
    public let exitCode: Int
    public let stdout: String
    public let stderr: String
    public let message: String
    
    public init(scriptPath: String, exitCode: Int, stdout: String = "", stderr: String = "") {
        self.scriptPath = scriptPath
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        
        var message = "Action script '\(scriptPath)' failed with exit code \(exitCode)"
        if !stderr.isEmpty {
            let truncatedStderr = String(stderr.prefix(500))
            message += ": \(truncatedStderr)"
        }
        self.message = message
    }
}