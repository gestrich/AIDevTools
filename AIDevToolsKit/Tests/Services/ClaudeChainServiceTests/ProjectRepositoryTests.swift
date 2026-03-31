import XCTest
import ClaudeChainSDK
@testable import ClaudeChainService
import Foundation

// Import test helpers
// createTempDirectory() is defined in TestHelpers.swift

/// Unit tests for ProjectRepository
/// Swift port of test_project_repository.py
final class ProjectRepositoryTests: XCTestCase {

    // MARK: - ProjectRepository Initialization Tests

    func testCreateRepositoryWithRepoName() {
        // Should create repository with GitHub repo name

        // Arrange & Act
        let repo = ProjectRepository(repo: "owner/repo-name", gitHubOperations: MockGitHubOperations())

        // Assert
        XCTAssertNotNil(repo)
    }

    // MARK: - Load Configuration Tests

    func testLoadConfigurationSuccess() throws {
        // Should load and parse configuration successfully

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: mockGitHubOps)
        let project = Project(name: "my-project")
        let yamlContent = """
assignee: alice
baseBranch: develop
"""

        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            XCTAssertEqual(repo, "owner/repo")
            XCTAssertEqual(branch, "main")
            XCTAssertEqual(filePath, "claude-chain/my-project/configuration.yml")
            return yamlContent
        }

        // Act
        let config = try repo.loadConfiguration(project: project, baseBranch: "main")

        // Assert
        XCTAssertNotNil(config)
        XCTAssertEqual(config.project, project)
        XCTAssertEqual(config.assignees, ["alice"])
        XCTAssertEqual(config.baseBranch, "develop")
    }

    func testLoadConfigurationReturnsDefaultWhenFileNotFound() throws {
        // Should return default config when configuration file doesn't exist

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: mockGitHubOps)
        let project = Project(name: "my-project")

        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            XCTAssertEqual(repo, "owner/repo")
            XCTAssertEqual(branch, "main")
            XCTAssertEqual(filePath, "claude-chain/my-project/configuration.yml")
            return nil
        }

        // Act
        let config = try repo.loadConfiguration(project: project, baseBranch: "main")

        // Assert - returns default config, not nil
        XCTAssertNotNil(config)
        XCTAssertEqual(config.project, project)
        XCTAssertEqual(config.assignees, [])
        XCTAssertNil(config.baseBranch)
    }

    func testLoadConfigurationWithCustomBranch() throws {
        // Should load configuration from custom branch

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: mockGitHubOps)
        let project = Project(name: "my-project")
        let yamlContent = "assignee: bob"

        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            XCTAssertEqual(repo, "owner/repo")
            XCTAssertEqual(branch, "develop")
            XCTAssertEqual(filePath, "claude-chain/my-project/configuration.yml")
            return yamlContent
        }

        // Act
        let config = try repo.loadConfiguration(project: project, baseBranch: "develop")

        // Assert
        XCTAssertNotNil(config)
        XCTAssertEqual(config.assignees, ["bob"])
    }

    func testLoadConfigurationWithCustomProjectBasePath() throws {
        // Should use custom project base path

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: mockGitHubOps)
        let project = Project(name: "my-project", basePath: "custom/path/my-project")
        let yamlContent = "assignee: alice"

        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            XCTAssertEqual(repo, "owner/repo")
            XCTAssertEqual(branch, "main")
            XCTAssertEqual(filePath, "custom/path/my-project/configuration.yml")
            return yamlContent
        }

        // Act
        let config = try repo.loadConfiguration(project: project, baseBranch: "main")

        // Assert
        XCTAssertNotNil(config)
        XCTAssertEqual(config.assignees, ["alice"])
    }

    func testLoadConfigurationHandlesEmptyConfig() throws {
        // Should handle configuration without assignee

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: mockGitHubOps)
        let project = Project(name: "my-project")
        let yamlContent = "baseBranch: main"

        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            return yamlContent
        }

        // Act
        let config = try repo.loadConfiguration(project: project, baseBranch: "main")

        // Assert
        XCTAssertNotNil(config)
        XCTAssertEqual(config.assignees, [])
        XCTAssertEqual(config.baseBranch, "main")
    }

    // MARK: - Load Configuration If Exists Tests

    func testLoadConfigurationIfExistsReturnsConfigWhenFound() throws {
        // Should return parsed config when file exists

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: mockGitHubOps)
        let project = Project(name: "my-project")
        let yamlContent = "assignee: alice"

        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            return yamlContent
        }

        // Act
        let config = try repo.loadConfigurationIfExists(project: project, baseBranch: "main")

        // Assert
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.assignees, ["alice"])
    }

    func testLoadConfigurationIfExistsReturnsNilWhenNotFound() throws {
        // Should return nil when file doesn't exist

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: mockGitHubOps)
        let project = Project(name: "my-project")

        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            return nil
        }

        // Act
        let config = try repo.loadConfigurationIfExists(project: project, baseBranch: "main")

        // Assert
        XCTAssertNil(config)
    }

    // MARK: - Load Spec Tests

    func testLoadSpecSuccess() throws {
        // Should load and parse spec.md successfully

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: mockGitHubOps)
        let project = Project(name: "my-project")
        let specContent = """
# Project Spec
- [ ] Task 1
- [ ] Task 2
- [x] Task 3
"""

        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            XCTAssertEqual(repo, "owner/repo")
            XCTAssertEqual(branch, "main")
            XCTAssertEqual(filePath, "claude-chain/my-project/spec.md")
            return specContent
        }

        // Act
        let spec = try repo.loadSpec(project: project, baseBranch: "main")

        // Assert
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.project, project)
        XCTAssertEqual(spec?.totalTasks, 3)
        XCTAssertEqual(spec?.completedTasks, 1)
    }

    func testLoadSpecReturnsNilWhenFileNotFound() throws {
        // Should return nil when spec file doesn't exist

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: mockGitHubOps)
        let project = Project(name: "my-project")

        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            XCTAssertEqual(repo, "owner/repo")
            XCTAssertEqual(branch, "main")
            XCTAssertEqual(filePath, "claude-chain/my-project/spec.md")
            return nil
        }

        // Act
        let spec = try repo.loadSpec(project: project, baseBranch: "main")

        // Assert
        XCTAssertNil(spec)
    }

    func testLoadSpecWithCustomBranch() throws {
        // Should load spec from custom branch

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: mockGitHubOps)
        let project = Project(name: "my-project")
        let specContent = "- [ ] Task 1"

        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            XCTAssertEqual(repo, "owner/repo")
            XCTAssertEqual(branch, "feature-branch")
            XCTAssertEqual(filePath, "claude-chain/my-project/spec.md")
            return specContent
        }

        // Act
        let spec = try repo.loadSpec(project: project, baseBranch: "feature-branch")

        // Assert
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.totalTasks, 1)
    }

    func testLoadSpecWithCustomProjectBasePath() throws {
        // Should use custom project base path

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: mockGitHubOps)
        let project = Project(name: "my-project", basePath: "custom/path/my-project")
        let specContent = "- [ ] Task 1"

        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            XCTAssertEqual(repo, "owner/repo")
            XCTAssertEqual(branch, "main")
            XCTAssertEqual(filePath, "custom/path/my-project/spec.md")
            return specContent
        }

        // Act
        let spec = try repo.loadSpec(project: project, baseBranch: "main")

        // Assert
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.totalTasks, 1)
    }

    func testLoadSpecWithEmptyContent() throws {
        // Should return nil for empty spec content (treated as not found)

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: mockGitHubOps)
        let project = Project(name: "my-project")
        let specContent = ""

        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            return specContent
        }

        // Act
        let spec = try repo.loadSpec(project: project, baseBranch: "main")

        // Assert
        // Empty string is treated as falsy, so returns nil
        XCTAssertNil(spec)
    }

    func testLoadSpecWithNoTasks() throws {
        // Should handle spec with no task items

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: mockGitHubOps)
        let project = Project(name: "my-project")
        let specContent = """
# Project Spec

This is just documentation without tasks.

## Notes
More text here.
"""

        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            return specContent
        }

        // Act
        let spec = try repo.loadSpec(project: project, baseBranch: "main")

        // Assert
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.totalTasks, 0)
    }

    // MARK: - Load Project Full Tests

    func testLoadProjectFullSuccess() throws {
        // Should load complete project data successfully

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: mockGitHubOps)

        // Mock responses for config and spec
        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            if filePath.contains("configuration.yml") {
                return "assignee: alice"
            } else if filePath.contains("spec.md") {
                return "- [ ] Task 1\n- [x] Task 2"
            }
            return nil
        }

        // Act
        let result = try repo.loadProjectFull(projectName: "my-project", baseBranch: "main")

        // Assert
        XCTAssertNotNil(result)
        let (project, config, spec) = result!

        XCTAssertEqual(project.name, "my-project")
        XCTAssertEqual(config.assignees, ["alice"])
        XCTAssertEqual(spec.totalTasks, 2)
        XCTAssertEqual(spec.completedTasks, 1)
    }

    func testLoadProjectFullUsesDefaultConfigWhenConfigMissing() throws {
        // Should use default config when configuration file is missing

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: mockGitHubOps)

        // Mock: spec exists, config doesn't
        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            if filePath.contains("spec.md") {
                return "- [ ] Task 1\n- [x] Task 2"
            }
            return nil // Config not found
        }

        // Act
        let result = try repo.loadProjectFull(projectName: "my-project", baseBranch: "main")

        // Assert - returns project with default config
        XCTAssertNotNil(result)
        let (project, config, spec) = result!

        XCTAssertEqual(project.name, "my-project")
        XCTAssertEqual(config.assignees, []) // Default config has no assignee
        XCTAssertNil(config.baseBranch)
        XCTAssertEqual(spec.totalTasks, 2)
    }

    func testLoadProjectFullReturnsNilWhenSpecMissing() throws {
        // Should return nil when spec file is missing

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: mockGitHubOps)

        // Mock: config exists, spec doesn't
        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            if filePath.contains("configuration.yml") {
                return "assignee: alice"
            }
            return nil
        }

        // Act
        let result = try repo.loadProjectFull(projectName: "my-project", baseBranch: "main")

        // Assert
        XCTAssertNil(result)
    }

    func testLoadProjectFullWithCustomBranch() throws {
        // Should load from custom branch

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: mockGitHubOps)

        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            XCTAssertEqual(branch, "develop") // Verify branch was used in calls
            if filePath.contains("configuration.yml") {
                return "assignee: alice"
            } else if filePath.contains("spec.md") {
                return "- [ ] Task 1"
            }
            return nil
        }

        // Act
        let result = try repo.loadProjectFull(projectName: "my-project", baseBranch: "develop")

        // Assert
        XCTAssertNotNil(result)
        let (project, config, spec) = result!
        XCTAssertEqual(project.name, "my-project")
        XCTAssertEqual(config.assignees, ["alice"])
        XCTAssertEqual(spec.totalTasks, 1)
    }

    func testLoadProjectFullCreatesProjectWithCorrectName() throws {
        // Should create Project object with correct name

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: mockGitHubOps)

        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            if filePath.contains("configuration.yml") {
                return "assignee: alice"
            } else if filePath.contains("spec.md") {
                return "- [ ] Task 1"
            }
            return nil
        }

        // Act
        let result = try repo.loadProjectFull(projectName: "custom-project-name", baseBranch: "main")

        // Assert
        XCTAssertNotNil(result)
        let (project, _, _) = result!
        XCTAssertEqual(project.name, "custom-project-name")
        XCTAssertEqual(project.basePath, "claude-chain/custom-project-name")
    }

    // MARK: - Local Filesystem Tests

    func testLoadLocalConfigurationSuccess() throws {
        // Should load and parse configuration from local filesystem

        // Arrange
        let tempDir = createTempDirectory()
        let projectDir = tempDir.appendingPathComponent("claude-chain/my-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let configContent = """
assignee: alice
baseBranch: develop
allowedTools: Read,Write,Edit
"""
        let configFile = projectDir.appendingPathComponent("configuration.yml")
        try configContent.write(to: configFile, atomically: true, encoding: .utf8)

        let project = Project(name: "my-project", basePath: projectDir.path)
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: MockGitHubOperations())

        // Act
        let config = try repo.loadLocalConfiguration(project: project)

        // Assert
        XCTAssertNotNil(config)
        XCTAssertEqual(config.project, project)
        XCTAssertEqual(config.assignees, ["alice"])
        XCTAssertEqual(config.baseBranch, "develop")
        XCTAssertEqual(config.allowedTools, "Read,Write,Edit")
    }

    func testLoadLocalConfigurationReturnsDefaultWhenFileNotFound() throws {
        // Should return default config when configuration file doesn't exist

        // Arrange
        let tempDir = createTempDirectory()
        let projectDir = tempDir.appendingPathComponent("claude-chain/my-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        // No config file created

        let project = Project(name: "my-project", basePath: projectDir.path)
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: MockGitHubOperations())

        // Act
        let config = try repo.loadLocalConfiguration(project: project)

        // Assert - returns default config, not nil
        XCTAssertNotNil(config)
        XCTAssertEqual(config.project, project)
        XCTAssertEqual(config.assignees, [])
        XCTAssertNil(config.baseBranch)
        XCTAssertNil(config.allowedTools)
    }

    func testLoadLocalSpecSuccess() throws {
        // Should load and parse spec.md from local filesystem

        // Arrange
        let tempDir = createTempDirectory()
        let projectDir = tempDir.appendingPathComponent("claude-chain/my-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let specContent = """
# Project Spec
- [ ] Task 1
- [ ] Task 2
- [x] Task 3
"""
        let specFile = projectDir.appendingPathComponent("spec.md")
        try specContent.write(to: specFile, atomically: true, encoding: .utf8)

        let project = Project(name: "my-project", basePath: projectDir.path)
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: MockGitHubOperations())

        // Act
        let spec = try repo.loadLocalSpec(project: project)

        // Assert
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.project, project)
        XCTAssertEqual(spec?.totalTasks, 3)
        XCTAssertEqual(spec?.completedTasks, 1)
    }

    func testLoadLocalSpecReturnsNilWhenFileNotFound() throws {
        // Should return nil when spec file doesn't exist

        // Arrange
        let tempDir = createTempDirectory()
        let projectDir = tempDir.appendingPathComponent("claude-chain/my-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        // No spec file created

        let project = Project(name: "my-project", basePath: projectDir.path)
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: MockGitHubOperations())

        // Act
        let spec = try repo.loadLocalSpec(project: project)

        // Assert
        XCTAssertNil(spec)
    }

    // MARK: - loadLocalReview Tests

    func testLoadLocalReviewReturnsContentWhenFileExists() throws {
        // Arrange
        let tempDir = createTempDirectory()
        let projectDir = tempDir.appendingPathComponent("claude-chain/my-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let reviewContent = "All Swift files must have a file-level comment."
        let reviewFile = projectDir.appendingPathComponent("review.md")
        try reviewContent.write(to: reviewFile, atomically: true, encoding: .utf8)

        let project = Project(name: "my-project", basePath: projectDir.path)
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: MockGitHubOperations())

        // Act
        let result = try repo.loadLocalReview(project: project)

        // Assert
        XCTAssertEqual(result, reviewContent)
    }

    func testLoadLocalReviewReturnsNilWhenFileIsMissing() throws {
        // Arrange
        let tempDir = createTempDirectory()
        let projectDir = tempDir.appendingPathComponent("claude-chain/my-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let project = Project(name: "my-project", basePath: projectDir.path)
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: MockGitHubOperations())

        // Act
        let result = try repo.loadLocalReview(project: project)

        // Assert
        XCTAssertNil(result)
    }

    func testLoadLocalReviewReturnsNilWhenFileIsEmpty() throws {
        // Arrange
        let tempDir = createTempDirectory()
        let projectDir = tempDir.appendingPathComponent("claude-chain/my-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let reviewFile = projectDir.appendingPathComponent("review.md")
        try "".write(to: reviewFile, atomically: true, encoding: .utf8)

        let project = Project(name: "my-project", basePath: projectDir.path)
        let repo = ProjectRepository(repo: "owner/repo", gitHubOperations: MockGitHubOperations())

        // Act
        let result = try repo.loadLocalReview(project: project)

        // Assert
        XCTAssertNil(result)
    }

    // MARK: - Integration Tests

    func testFullWorkflowWithRealisticData() throws {
        // Should handle complete workflow with realistic project data

        // Arrange
        let mockGitHubOps = MockGitHubOperations()
        let repo = ProjectRepository(repo: "acme/web-app", gitHubOperations: mockGitHubOps)

        let realisticConfig = """
assignee: dev1
baseBranch: develop
allowedTools: Read,Write,Edit,Bash
stalePRDays: 14
"""

        let realisticSpec = """
# Web Application Refactoring

## Overview
This project refactors the authentication system.

## Tasks

- [x] Analyze current authentication flow
- [x] Design new architecture
- [ ] Implement OAuth2 provider
- [ ] Add JWT token management
- [ ] Create user session service
- [ ] Write integration tests
- [ ] Update documentation

## Notes
Ensure backward compatibility with existing sessions.
"""

        mockGitHubOps.mockGetFileFromBranch = { repo, branch, filePath in
            if filePath.contains("configuration.yml") {
                return realisticConfig
            } else if filePath.contains("spec.md") {
                return realisticSpec
            }
            return nil
        }

        // Act
        let result = try repo.loadProjectFull(projectName: "auth-refactor", baseBranch: "main")

        // Assert - Verify complete structure
        XCTAssertNotNil(result)
        let (project, config, spec) = result!

        // Project assertions
        XCTAssertEqual(project.name, "auth-refactor")
        XCTAssertEqual(project.configPath, "claude-chain/auth-refactor/configuration.yml")

        // Config assertions
        XCTAssertEqual(config.assignees, ["dev1"])
        XCTAssertEqual(config.baseBranch, "develop")
        XCTAssertEqual(config.allowedTools, "Read,Write,Edit,Bash")
        XCTAssertEqual(config.stalePRDays, 14)

        // Spec assertions
        XCTAssertEqual(spec.totalTasks, 7)
        XCTAssertEqual(spec.completedTasks, 2)
        XCTAssertEqual(spec.pendingTasks, 5)

        let nextTask = spec.getNextAvailableTask()
        XCTAssertNotNil(nextTask)
        XCTAssertEqual(nextTask?.description, "Implement OAuth2 provider")
        XCTAssertEqual(nextTask?.index, 3)

        let pendingIndices = spec.getPendingTaskIndices()
        XCTAssertEqual(pendingIndices, [3, 4, 5, 6, 7])
    }
}

// MARK: - Mock Implementation

/// Mock implementation of GitHubOperationsProtocol for testing
class MockGitHubOperations: GitHubOperationsProtocol {
    var mockGetFileFromBranch: ((String, String, String) throws -> String?)?

    func getFileFromBranch(repo: String, branch: String, filePath: String) throws -> String? {
        if let mock = mockGetFileFromBranch {
            return try mock(repo, branch, filePath)
        }
        return nil
    }
}
