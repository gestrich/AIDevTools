/// Unit tests for domain exception classes
import XCTest
@testable import ClaudeChainService

final class TestExceptionHierarchy: XCTestCase {
    /// Test suite for exception class hierarchy and inheritance
    
    func testBaseExceptionCanBeRaised() {
        /// Should be able to raise and catch ContinuousRefactoringError
        let message = "Test error"
        let error = ContinuousRefactoringError(message)
        XCTAssertEqual(error.message, message)
    }
    
    func testBaseExceptionIncludesMessage() {
        /// Should store error message in exception
        let message = "Something went wrong"
        let error = ContinuousRefactoringError(message)
        XCTAssertEqual(error.message, message)
    }
    
    func testConfigurationErrorInheritsFromBase() {
        /// ConfigurationError should inherit from Error
        let error = ConfigurationError("Config issue")
        XCTAssertTrue(error is Error)
    }
    
    func testFileNotFoundErrorInheritsFromBase() {
        /// FileNotFoundError should inherit from Error
        let error = FileNotFoundError("File missing")
        XCTAssertTrue(error is Error)
    }
    
    func testGitErrorInheritsFromBase() {
        /// GitError should inherit from Error
        let error = GitError("Git failure")
        XCTAssertTrue(error is Error)
    }
    
    func testGitHubAPIErrorInheritsFromBase() {
        /// GitHubAPIError should inherit from Error
        let error = GitHubAPIError("API failure")
        XCTAssertTrue(error is Error)
    }
}

final class TestConfigurationError: XCTestCase {
    /// Test suite for ConfigurationError exception
    
    func testCanCatchConfigurationError() {
        /// Should be able to catch ConfigurationError specifically
        let message = "Invalid config file"
        
        do {
            throw ConfigurationError(message)
        } catch let error as ConfigurationError {
            XCTAssertEqual(error.message, message)
        } catch {
            XCTFail("Should have caught ConfigurationError")
        }
    }
    
    func testCanCatchAsBaseException() {
        /// Should be able to catch ConfigurationError as Error type
        do {
            throw ConfigurationError("Config problem")
        } catch {
            // Successfully caught as Error
            XCTAssertTrue(error is ConfigurationError)
        }
    }
}

final class TestFileNotFoundError: XCTestCase {
    /// Test suite for FileNotFoundError exception
    
    func testCanCatchFileNotFoundError() {
        /// Should be able to catch FileNotFoundError specifically
        let message = "spec.md not found"
        
        do {
            throw FileNotFoundError(message)
        } catch let error as FileNotFoundError {
            XCTAssertEqual(error.message, message)
        } catch {
            XCTFail("Should have caught FileNotFoundError")
        }
    }
    
    func testCanCatchAsBaseException() {
        /// Should be able to catch FileNotFoundError as Error type
        do {
            throw FileNotFoundError("Missing file")
        } catch {
            // Successfully caught as Error
            XCTAssertTrue(error is FileNotFoundError)
        }
    }
}

final class TestGitError: XCTestCase {
    /// Test suite for GitError exception
    
    func testCanCatchGitError() {
        /// Should be able to catch GitError specifically
        let message = "git command failed: exit code 1"
        
        do {
            throw GitError(message)
        } catch let error as GitError {
            XCTAssertTrue(error.message.contains("git command failed"))
        } catch {
            XCTFail("Should have caught GitError")
        }
    }
    
    func testCanCatchAsBaseException() {
        /// Should be able to catch GitError as Error type
        do {
            throw GitError("Git operation failed")
        } catch {
            // Successfully caught as Error
            XCTAssertTrue(error is GitError)
        }
    }
}

final class TestGitHubAPIError: XCTestCase {
    /// Test suite for GitHubAPIError exception
    
    func testCanCatchGitHubAPIError() {
        /// Should be able to catch GitHubAPIError specifically
        let message = "GitHub API rate limit exceeded"
        
        do {
            throw GitHubAPIError(message)
        } catch let error as GitHubAPIError {
            XCTAssertTrue(error.message.contains("rate limit exceeded"))
        } catch {
            XCTFail("Should have caught GitHubAPIError")
        }
    }
    
    func testCanCatchAsBaseException() {
        /// Should be able to catch GitHubAPIError as Error type
        do {
            throw GitHubAPIError("API call failed")
        } catch {
            // Successfully caught as Error
            XCTAssertTrue(error is GitHubAPIError)
        }
    }
}

final class TestExceptionCatchPatterns: XCTestCase {
    /// Test suite for common exception catching patterns
    
    func testCanCatchAllCustomExceptionsWithBase() {
        /// Should catch any custom exception using Error type
        let exceptions: [Error] = [
            ConfigurationError("Config error"),
            FileNotFoundError("File error"),
            GitError("Git error"),
            GitHubAPIError("API error"),
        ]
        
        for error in exceptions {
            do {
                throw error
            } catch {
                // Successfully caught as Error
                XCTAssertTrue(error is Error)
            }
        }
    }
    
    func testExceptionsPreserveOriginalMessage() {
        /// Should preserve error messages across all exception types
        let testCases: [(Error.Type, String)] = [
            (ConfigurationError.self, "Invalid reviewers configuration"),
            (FileNotFoundError.self, "Could not find configuration.yml"),
            (GitError.self, "Failed to create branch"),
            (GitHubAPIError.self, "Authentication failed"),
        ]
        
        for (_, message) in testCases {
            let configError = ConfigurationError(message)
            XCTAssertEqual(configError.message, message)
            
            let fileError = FileNotFoundError(message)
            XCTAssertEqual(fileError.message, message)
            
            let gitError = GitError(message)
            XCTAssertEqual(gitError.message, message)
            
            let apiError = GitHubAPIError(message)
            XCTAssertEqual(apiError.message, message)
        }
    }
}