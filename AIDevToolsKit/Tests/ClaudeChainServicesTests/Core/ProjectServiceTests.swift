/**
 * Tests for project detection logic
 * 
 * Swift port of tests/unit/services/core/test_project_service.py
 */

import XCTest
@testable import ClaudeChainServices
@testable import ClaudeChainService
@testable import ClaudeChainInfrastructure

final class ProjectServiceTests: XCTestCase {
    
    // MARK: - DetectProjectsFromMerge Tests
    
    func testDetectSingleProjectFromSpecChange() {
        /// Should detect a single project when one spec.md is changed
        
        // Arrange
        let changedFiles = [
            "claude-chain/my-project/spec.md",
            "README.md",
            "src/main.py"
        ]
        
        // Act
        let projects = ProjectService.detectProjectsFromMerge(changedFiles: changedFiles)
        
        // Assert
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "my-project")
    }
    
    func testDetectMultipleProjectsFromSpecChanges() {
        /// Should detect multiple projects when multiple spec.md files are changed
        
        // Arrange
        let changedFiles = [
            "claude-chain/project-a/spec.md",
            "claude-chain/project-b/spec.md",
            "README.md"
        ]
        
        // Act
        let projects = ProjectService.detectProjectsFromMerge(changedFiles: changedFiles)
        
        // Assert
        XCTAssertEqual(projects.count, 2)
        let projectNames = projects.map { $0.name }
        XCTAssertTrue(projectNames.contains("project-a"))
        XCTAssertTrue(projectNames.contains("project-b"))
    }
    
    func testReturnsEmptyListWhenNoSpecFilesChanged() {
        /// Should return empty list when no spec.md files are changed
        
        // Arrange
        let changedFiles = [
            "src/main.py",
            "README.md",
            "claude-chain/my-project/configuration.yml"  // Not spec.md
        ]
        
        // Act
        let projects = ProjectService.detectProjectsFromMerge(changedFiles: changedFiles)
        
        // Assert
        XCTAssertEqual(projects.count, 0)
    }
    
    func testReturnsEmptyListForEmptyFileList() {
        /// Should return empty list when file list is empty
        
        // Arrange
        let changedFiles: [String] = []
        
        // Act
        let projects = ProjectService.detectProjectsFromMerge(changedFiles: changedFiles)
        
        // Assert
        XCTAssertEqual(projects.count, 0)
    }
    
    func testIgnoresSpecFilesNotInClaudeChainDirectory() {
        /// Should ignore spec.md files outside claude-chain directory
        
        // Arrange
        let changedFiles = [
            "docs/spec.md",  // Not in claude-chain/
            "other-project/spec.md",  // Not in claude-chain/
            "spec.md"  // Root level
        ]
        
        // Act
        let projects = ProjectService.detectProjectsFromMerge(changedFiles: changedFiles)
        
        // Assert
        XCTAssertEqual(projects.count, 0)
    }
    
    func testIgnoresNestedSpecFiles() {
        /// Should ignore spec.md files nested too deeply
        
        // Arrange
        let changedFiles = [
            "claude-chain/project/subdir/spec.md",  // Too deep
            "claude-chain/project/docs/spec.md"  // Too deep
        ]
        
        // Act
        let projects = ProjectService.detectProjectsFromMerge(changedFiles: changedFiles)
        
        // Assert
        XCTAssertEqual(projects.count, 0)
    }
    
    func testReturnsSortedProjects() {
        /// Should return projects sorted by name
        
        // Arrange
        let changedFiles = [
            "claude-chain/zebra-project/spec.md",
            "claude-chain/alpha-project/spec.md",
            "claude-chain/middle-project/spec.md"
        ]
        
        // Act
        let projects = ProjectService.detectProjectsFromMerge(changedFiles: changedFiles)
        
        // Assert
        XCTAssertEqual(projects.count, 3)
        XCTAssertEqual(projects[0].name, "alpha-project")
        XCTAssertEqual(projects[1].name, "middle-project")
        XCTAssertEqual(projects[2].name, "zebra-project")
    }
    
    func testHandlesProjectNamesWithHyphens() {
        /// Should correctly extract project names containing hyphens
        
        // Arrange
        let changedFiles = ["claude-chain/my-complex-project-name/spec.md"]
        
        // Act
        let projects = ProjectService.detectProjectsFromMerge(changedFiles: changedFiles)
        
        // Assert
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "my-complex-project-name")
    }
    
    func testReturnsProjectObjectsWithCorrectPaths() {
        /// Should return Project objects with correct path properties
        
        // Arrange
        let changedFiles = ["claude-chain/test-project/spec.md"]
        
        // Act
        let projects = ProjectService.detectProjectsFromMerge(changedFiles: changedFiles)
        
        // Assert
        XCTAssertEqual(projects.count, 1)
        let project = projects[0]
        XCTAssertEqual(project.name, "test-project")
        XCTAssertEqual(project.specPath, "claude-chain/test-project/spec.md")
        XCTAssertEqual(project.configPath, "claude-chain/test-project/configuration.yml")
        XCTAssertEqual(project.basePath, "claude-chain/test-project")
    }
    
    func testDeduplicatesSameProject() {
        /// Should not duplicate projects even if multiple files for same project changed
        
        // Arrange - Same project, spec appears twice (shouldn't happen but test robustness)
        let changedFiles = [
            "claude-chain/my-project/spec.md",
            "claude-chain/my-project/spec.md"  // Duplicate
        ]
        
        // Act
        let projects = ProjectService.detectProjectsFromMerge(changedFiles: changedFiles)
        
        // Assert
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "my-project")
    }
}