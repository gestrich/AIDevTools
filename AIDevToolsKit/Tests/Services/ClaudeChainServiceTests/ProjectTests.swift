/// Unit tests for Project domain model
import XCTest
import Foundation
@testable import ClaudeChainService

final class TestProjectInitialization: XCTestCase {
    /// Test suite for Project initialization
    
    func testCreateProjectWithDefaultBasePath() {
        /// Should create project with default base path
        let project = Project(name: "my-project")
        
        XCTAssertEqual(project.name, "my-project")
        XCTAssertEqual(project.basePath, "claude-chain/my-project")
    }
    
    func testCreateProjectWithCustomBasePath() {
        /// Should create project with custom base path
        let project = Project(name: "my-project", basePath: "custom/path/my-project")
        
        XCTAssertEqual(project.name, "my-project")
        XCTAssertEqual(project.basePath, "custom/path/my-project")
    }
}

final class TestProjectPathProperties: XCTestCase {
    /// Test suite for Project path properties
    
    func testConfigPathProperty() {
        /// Should return correct config path
        let project = Project(name: "my-project")
        
        let configPath = project.configPath
        
        XCTAssertEqual(configPath, "claude-chain/my-project/configuration.yml")
    }
    
    func testSpecPathProperty() {
        /// Should return correct spec path
        let project = Project(name: "my-project")
        
        let specPath = project.specPath
        
        XCTAssertEqual(specPath, "claude-chain/my-project/spec.md")
    }
    
    func testPrTemplatePathProperty() {
        /// Should return correct PR template path
        let project = Project(name: "my-project")
        
        let prTemplatePath = project.prTemplatePath
        
        XCTAssertEqual(prTemplatePath, "claude-chain/my-project/pr-template.md")
    }
    
    func testMetadataFilePathProperty() {
        /// Should return correct metadata file path
        let project = Project(name: "my-project")
        
        let metadataPath = project.metadataFilePath
        
        XCTAssertEqual(metadataPath, "my-project.json")
    }
    
    func testPathsWithCustomBasePath() {
        /// Should construct correct paths with custom base path
        let project = Project(name: "my-project", basePath: "custom/path/my-project")
        
        XCTAssertEqual(project.configPath, "custom/path/my-project/configuration.yml")
        XCTAssertEqual(project.specPath, "custom/path/my-project/spec.md")
        XCTAssertEqual(project.prTemplatePath, "custom/path/my-project/pr-template.md")
        // metadata_file_path should still be just the project name
        XCTAssertEqual(project.metadataFilePath, "my-project.json")
    }
}

final class TestProjectFromConfigPath: XCTestCase {
    /// Test suite for Project.fromConfigPath factory method
    
    func testFromConfigPathStandardFormat() {
        /// Should extract project name from standard config path
        let configPath = "claude-chain/my-project/configuration.yml"
        
        let project = Project.fromConfigPath(configPath)
        
        XCTAssertEqual(project.name, "my-project")
        XCTAssertEqual(project.basePath, "claude-chain/my-project")
    }
    
    func testFromConfigPathWithDifferentBaseDir() {
        /// Should extract project name from config path with different base directory
        let configPath = "custom/my-project/configuration.yml"
        
        let project = Project.fromConfigPath(configPath)
        
        XCTAssertEqual(project.name, "my-project")
        // Note: from_config_path uses default base_path construction
        XCTAssertEqual(project.basePath, "claude-chain/my-project")
    }
    
    func testFromConfigPathWithNestedDirectories() {
        /// Should extract project name from deeply nested config path
        let configPath = "deeply/nested/my-project/configuration.yml"
        
        let project = Project.fromConfigPath(configPath)
        
        XCTAssertEqual(project.name, "my-project")
    }
}

final class TestProjectFromBranchName: XCTestCase {
    /// Test suite for Project.fromBranchName factory method
    
    func testFromBranchNameValidHashBasedBranch() {
        /// Should extract project from valid hash-based branch name
        let branchName = "claude-chain-my-project-a1b2c3d4"
        
        let project = Project.fromBranchName(branchName)
        
        XCTAssertNotNil(project)
        XCTAssertEqual(project?.name, "my-project")
        XCTAssertEqual(project?.basePath, "claude-chain/my-project")
    }
    
    func testFromBranchNameWithHyphenatedProjectName() {
        /// Should extract project with hyphens from hash-based branch name
        let branchName = "claude-chain-my-complex-project-name-12345678"
        
        let project = Project.fromBranchName(branchName)
        
        XCTAssertNotNil(project)
        XCTAssertEqual(project?.name, "my-complex-project-name")
    }
    
    func testFromBranchNameInvalidFormatReturnsNil() {
        /// Should return nil for invalid branch name format
        let invalidBranches = [
            "invalid-branch-name",
            "claude-chain-project",  // Missing hash
            "claude-chain-abc",  // Missing project name
            "main",
            "feature/something",
            "claude-chain-project-5",  // Index instead of hash
            "claude-chain-project-123",  // Index instead of hash
            "claude-chain-project-abcdefg",  // Hash too short (7 chars)
            "claude-chain-project-abcdefghi",  // Hash too long (9 chars)
            "claude-chain-project-ABCDEF12",  // Uppercase not allowed
            "claude-chain-project-xyz12345",  // Invalid hex chars (x, y, z)
        ]
        
        for branchName in invalidBranches {
            let project = Project.fromBranchName(branchName)
            XCTAssertNil(project, "Should return nil for: \(branchName)")
        }
    }
    
    func testFromBranchNameVariousHexHashes() {
        /// Should extract project from branch with various valid hex hashes
        let testCases = [
            ("claude-chain-my-project-00000000", "my-project"),
            ("claude-chain-my-project-ffffffff", "my-project"),
            ("claude-chain-my-project-12abcdef", "my-project"),
            ("claude-chain-other-proj-a1b2c3d4", "other-proj"),
        ]
        
        for (branchName, expectedName) in testCases {
            let project = Project.fromBranchName(branchName)
            XCTAssertNotNil(project, "Should parse: \(branchName)")
            XCTAssertEqual(project?.name, expectedName)
        }
    }
}

final class TestProjectFindAll: XCTestCase {
    /// Test suite for Project.findAll factory method
    
    func testFindAllDiscoversMultipleProjects() throws {
        /// Should discover all valid projects in directory
        let tempDir = FileManager.default.temporaryDirectory
        let baseDir = tempDir.appendingPathComponent("claude-chain-\(UUID())")
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }
        
        // Create valid projects (projects are discovered by spec.md)
        for projectName in ["project-a", "project-b", "project-c"] {
            let projectDir = baseDir.appendingPathComponent(projectName)
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
            try "- [ ] Task 1".write(to: projectDir.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
        }
        
        // Act
        let projects = Project.findAll(baseDir: baseDir.path)
        
        // Assert
        XCTAssertEqual(projects.count, 3)
        let projectNames = projects.map { $0.name }
        XCTAssertTrue(projectNames.contains("project-a"))
        XCTAssertTrue(projectNames.contains("project-b"))
        XCTAssertTrue(projectNames.contains("project-c"))
    }
    
    func testFindAllReturnsSortedProjects() throws {
        /// Should return projects sorted by name
        let tempDir = FileManager.default.temporaryDirectory
        let baseDir = tempDir.appendingPathComponent("claude-chain-\(UUID())")
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }
        
        // Create projects in non-alphabetical order
        for projectName in ["zebra", "alpha", "middle"] {
            let projectDir = baseDir.appendingPathComponent(projectName)
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
            try "- [ ] Task 1".write(to: projectDir.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
        }
        
        // Act
        let projects = Project.findAll(baseDir: baseDir.path)
        
        // Assert
        XCTAssertEqual(projects.count, 3)
        XCTAssertEqual(projects.map { $0.name }, ["alpha", "middle", "zebra"])
    }
    
    func testFindAllIgnoresDirectoriesWithoutSpec() throws {
        /// Should ignore directories without spec.md
        let tempDir = FileManager.default.temporaryDirectory
        let baseDir = tempDir.appendingPathComponent("claude-chain-\(UUID())")
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }
        
        // Valid project (has spec.md)
        let validProject = baseDir.appendingPathComponent("valid-project")
        try FileManager.default.createDirectory(at: validProject, withIntermediateDirectories: true)
        try "- [ ] Task 1".write(to: validProject.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
        
        // Invalid projects (no spec.md file)
        try FileManager.default.createDirectory(at: baseDir.appendingPathComponent("invalid-project-1"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: baseDir.appendingPathComponent("invalid-project-2"), withIntermediateDirectories: true)
        
        // Act
        let projects = Project.findAll(baseDir: baseDir.path)
        
        // Assert
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "valid-project")
    }
    
    func testFindAllDiscoversProjectsWithoutConfig() throws {
        /// Should discover projects that have spec.md but no configuration.yml
        let tempDir = FileManager.default.temporaryDirectory
        let baseDir = tempDir.appendingPathComponent("claude-chain-\(UUID())")
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }
        
        // Project with spec.md only (no configuration.yml)
        let specOnlyProject = baseDir.appendingPathComponent("spec-only-project")
        try FileManager.default.createDirectory(at: specOnlyProject, withIntermediateDirectories: true)
        try "- [ ] Task 1".write(to: specOnlyProject.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
        
        // Project with both spec.md and configuration.yml
        let fullProject = baseDir.appendingPathComponent("full-project")
        try FileManager.default.createDirectory(at: fullProject, withIntermediateDirectories: true)
        try "- [ ] Task 1".write(to: fullProject.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
        try "reviewers: []".write(to: fullProject.appendingPathComponent("configuration.yml"), atomically: true, encoding: .utf8)
        
        // Act
        let projects = Project.findAll(baseDir: baseDir.path)
        
        // Assert
        XCTAssertEqual(projects.count, 2)
        let projectNames = projects.map { $0.name }
        XCTAssertTrue(projectNames.contains("spec-only-project"))
        XCTAssertTrue(projectNames.contains("full-project"))
    }
    
    func testFindAllIgnoresDirectoriesWithOnlyConfig() throws {
        /// Should ignore directories that have configuration.yml but no spec.md
        let tempDir = FileManager.default.temporaryDirectory
        let baseDir = tempDir.appendingPathComponent("claude-chain-\(UUID())")
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }
        
        // Directory with only configuration.yml (not a valid project)
        let configOnlyDir = baseDir.appendingPathComponent("config-only")
        try FileManager.default.createDirectory(at: configOnlyDir, withIntermediateDirectories: true)
        try "reviewers: []".write(to: configOnlyDir.appendingPathComponent("configuration.yml"), atomically: true, encoding: .utf8)
        
        // Valid project with spec.md
        let validProject = baseDir.appendingPathComponent("valid-project")
        try FileManager.default.createDirectory(at: validProject, withIntermediateDirectories: true)
        try "- [ ] Task 1".write(to: validProject.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
        
        // Act
        let projects = Project.findAll(baseDir: baseDir.path)
        
        // Assert
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "valid-project")
    }
    
    func testFindAllIgnoresFilesInBaseDir() throws {
        /// Should ignore files (not directories) in base directory
        let tempDir = FileManager.default.temporaryDirectory
        let baseDir = tempDir.appendingPathComponent("claude-chain-\(UUID())")
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }
        
        // Create a valid project
        let projectDir = baseDir.appendingPathComponent("my-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try "- [ ] Task 1".write(to: projectDir.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
        
        // Create some files that should be ignored
        try "# Readme".write(to: baseDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "content".write(to: baseDir.appendingPathComponent("some-file.txt"), atomically: true, encoding: .utf8)
        
        // Act
        let projects = Project.findAll(baseDir: baseDir.path)
        
        // Assert
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "my-project")
    }
    
    func testFindAllReturnsEmptyListWhenDirectoryNotExists() {
        /// Should return empty list when base directory doesn't exist
        let tempDir = FileManager.default.temporaryDirectory
        let nonExistentDir = tempDir.appendingPathComponent("non-existent-\(UUID())")
        
        // Act
        let projects = Project.findAll(baseDir: nonExistentDir.path)
        
        // Assert
        XCTAssertEqual(projects, [])
    }
    
    func testFindAllWithCustomBaseDir() throws {
        /// Should discover projects in custom base directory
        let tempDir = FileManager.default.temporaryDirectory
        let customDir = tempDir.appendingPathComponent("custom-projects-\(UUID())")
        try FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: customDir) }
        
        let projectDir = customDir.appendingPathComponent("my-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try "- [ ] Task 1".write(to: projectDir.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
        
        // Act
        let projects = Project.findAll(baseDir: customDir.path)
        
        // Assert
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "my-project")
    }
}

final class TestProjectEquality: XCTestCase {
    /// Test suite for Project equality and hashing
    
    func testEqualitySameNameAndBasePath() {
        /// Should be equal when name and basePath match
        let project1 = Project(name: "my-project")
        let project2 = Project(name: "my-project")
        
        XCTAssertEqual(project1, project2)
    }
    
    func testEqualityDifferentNames() {
        /// Should not be equal when names differ
        let project1 = Project(name: "project-a")
        let project2 = Project(name: "project-b")
        
        XCTAssertNotEqual(project1, project2)
    }
    
    func testEqualityDifferentBasePaths() {
        /// Should not be equal when base paths differ
        let project1 = Project(name: "my-project", basePath: "claude-chain/my-project")
        let project2 = Project(name: "my-project", basePath: "custom/my-project")
        
        XCTAssertNotEqual(project1, project2)
    }
    
    func testHashSameForEqualProjects() {
        /// Should have same hash for equal projects
        let project1 = Project(name: "my-project")
        let project2 = Project(name: "my-project")
        
        XCTAssertEqual(project1.hashValue, project2.hashValue)
    }
    
    func testHashDifferentForDifferentProjects() {
        /// Should have different hash for different projects
        let project1 = Project(name: "project-a")
        let project2 = Project(name: "project-b")
        
        XCTAssertNotEqual(project1.hashValue, project2.hashValue)
    }
    
    func testCanUseInSet() {
        /// Should be usable in sets
        let project1 = Project(name: "project-a")
        let project2 = Project(name: "project-b")
        let project3 = Project(name: "project-a")  // Duplicate of project1
        
        let projectSet: Set<Project> = [project1, project2, project3]
        
        XCTAssertEqual(projectSet.count, 2)  // Only unique projects
        XCTAssertTrue(projectSet.contains(project1))
        XCTAssertTrue(projectSet.contains(project2))
    }
    
    func testCanUseAsDictKey() {
        /// Should be usable as dictionary keys
        let project1 = Project(name: "project-a")
        let project2 = Project(name: "project-b")
        
        let projectDict = [
            project1: "data-a",
            project2: "data-b"
        ]
        
        XCTAssertEqual(projectDict[project1], "data-a")
        XCTAssertEqual(projectDict[project2], "data-b")
    }
}

final class TestProjectDescription: XCTestCase {
    /// Test suite for Project string representation
    
    func testDescriptionContainsNameAndBasePath() {
        /// Should have readable string representation
        let project = Project(name: "my-project")
        
        let description = project.description
        
        XCTAssertTrue(description.contains("Project"))
        XCTAssertTrue(description.contains("my-project"))
        XCTAssertTrue(description.contains("claude-chain/my-project"))
    }
    
    func testDescriptionWithCustomBasePath() {
        /// Should include custom base path in representation
        let project = Project(name: "my-project", basePath: "custom/path")
        
        let description = project.description
        
        XCTAssertTrue(description.contains("my-project"))
        XCTAssertTrue(description.contains("custom/path"))
    }
}