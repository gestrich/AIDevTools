/// Unit tests for ProjectConfiguration domain model
import XCTest
import Foundation
@testable import ClaudeChainService

class ProjectConfigurationTests: XCTestCase {
    
    // MARK: - ProjectConfiguration Default Factory Tests
    
    func testDefaultCreatesConfigWithNoAssignee() throws {
        // Should create config with no assignees
        // Arrange
        let project = Project(name: "my-project")
        
        // Act
        let config = ProjectConfiguration.default(project: project)
        
        // Assert
        XCTAssertEqual(config.assignees, [] as [String])
    }
    
    func testDefaultCreatesConfigWithNoBaseBranch() throws {
        // Should create config with no base branch override
        // Arrange
        let project = Project(name: "my-project")
        
        // Act
        let config = ProjectConfiguration.default(project: project)
        
        // Assert
        XCTAssertNil(config.baseBranch)
    }
    
    func testDefaultPreservesProjectReference() throws {
        // Should preserve the project reference
        // Arrange
        let project = Project(name: "my-project")
        
        // Act
        let config = ProjectConfiguration.default(project: project)
        
        // Assert
        XCTAssertEqual(config.project, project)
        XCTAssertEqual(config.project.name, "my-project")
    }
    
    func testDefaultGetBaseBranchReturnsWorkflowDefault() throws {
        // Default config should fall back to workflow's default base branch
        // Arrange
        let project = Project(name: "my-project")
        let config = ProjectConfiguration.default(project: project)
        
        // Act
        let baseBranch = config.getBaseBranch(defaultBaseBranch: "main")
        
        // Assert
        XCTAssertEqual(baseBranch, "main")
    }
    
    func testDefaultToDictFormat() throws {
        // Default config should serialize correctly
        // Arrange
        let project = Project(name: "my-project")
        let config = ProjectConfiguration.default(project: project)
        
        // Act
        let result = config.toDict()
        
        // Assert
        let expected: [String: Any] = ["project": "my-project"]
        XCTAssertTrue(NSDictionary(dictionary: result).isEqual(to: expected))
        XCTAssertNil(result["baseBranch"])
        XCTAssertNil(result["assignees"])
    }
    
    // MARK: - ProjectConfiguration fromYAMLString Factory Tests
    
    func testFromYAMLStringWithAssignee() throws {
        // Legacy singular assignee in YAML should be folded into assignees list
        // Arrange
        let project = Project(name: "my-project")
        let yamlContent = """
assignee: alice
"""
        
        // Act
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        
        // Assert
        XCTAssertEqual(config.project, project)
        XCTAssertEqual(config.assignees, ["alice"])
    }
    
    func testFromYAMLStringWithoutAssignee() throws {
        // Should have empty assignees when not specified
        // Arrange
        let project = Project(name: "my-project")
        let yamlContent = """
other_setting: value
"""
        
        // Act
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        
        // Assert
        XCTAssertEqual(config.assignees, [] as [String])
    }
    
    // MARK: - ProjectConfiguration toDict Tests
    
    func testToDictWithAssignees() throws {
        // Should include assignees in dict when set
        // Arrange
        let project = Project(name: "my-project")
        let config = ProjectConfiguration(project: project, assignees: ["alice"])
        
        // Act
        let result = config.toDict()
        
        // Assert
        XCTAssertEqual(result["project"] as? String, "my-project")
        XCTAssertEqual(result["assignees"] as? [String], ["alice"])
    }
    
    func testToDictWithoutAssignees() throws {
        // Should not include assignees in dict when empty
        // Arrange
        let project = Project(name: "my-project")
        let config = ProjectConfiguration(project: project)
        
        // Act
        let result = config.toDict()
        
        // Assert
        let expected: [String: Any] = ["project": "my-project"]
        XCTAssertTrue(NSDictionary(dictionary: result).isEqual(to: expected))
        XCTAssertNil(result["assignees"])
    }
    
    // MARK: - ProjectConfiguration Base Branch Tests
    
    func testFromYAMLStringParsesBaseBranch() throws {
        // Should parse baseBranch from YAML configuration
        // Arrange
        let project = Project(name: "my-project")
        let yamlContent = """
assignee: alice
baseBranch: develop
"""
        
        // Act
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        
        // Assert
        XCTAssertEqual(config.baseBranch, "develop")
    }
    
    func testFromYAMLStringBaseBranchIsNoneWhenNotSpecified() throws {
        // Should have None base_branch when not specified in YAML
        // Arrange
        let project = Project(name: "my-project")
        let yamlContent = """
assignee: alice
"""
        
        // Act
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        
        // Assert
        XCTAssertNil(config.baseBranch)
    }
    
    func testGetBaseBranchReturnsConfigValueWhenSet() throws {
        // Should return config's base_branch when it is set
        // Arrange
        let project = Project(name: "my-project")
        let config = ProjectConfiguration(project: project, baseBranch: "develop")
        
        // Act
        let result = config.getBaseBranch(defaultBaseBranch: "main")
        
        // Assert
        XCTAssertEqual(result, "develop")
    }
    
    func testGetBaseBranchReturnsDefaultWhenNotSet() throws {
        // Should return default_base_branch when config's base_branch is not set
        // Arrange
        let project = Project(name: "my-project")
        let config = ProjectConfiguration(project: project, baseBranch: nil)
        
        // Act
        let result = config.getBaseBranch(defaultBaseBranch: "main")
        
        // Assert
        XCTAssertEqual(result, "main")
    }
    
    func testToDictIncludesBaseBranchWhenSet() throws {
        // Should include baseBranch in dict when base_branch is set
        // Arrange
        let project = Project(name: "my-project")
        let config = ProjectConfiguration(project: project, baseBranch: "develop")
        
        // Act
        let result = config.toDict()
        
        // Assert
        XCTAssertTrue(result.keys.contains("baseBranch"))
        XCTAssertEqual(result["baseBranch"] as? String, "develop")
    }
    
    func testToDictExcludesBaseBranchWhenNotSet() throws {
        // Should not include baseBranch in dict when base_branch is None
        // Arrange
        let project = Project(name: "my-project")
        let config = ProjectConfiguration(project: project, baseBranch: nil)
        
        // Act
        let result = config.toDict()
        
        // Assert
        XCTAssertFalse(result.keys.contains("baseBranch"))
    }
    
    func testBaseBranchWithSpecialCharacters() throws {
        // Should handle base_branch with special characters like slashes
        // Arrange
        let project = Project(name: "my-project")
        let yamlContent = """
assignee: alice
baseBranch: feature/my-branch
"""
        
        // Act
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        
        // Assert
        XCTAssertEqual(config.baseBranch, "feature/my-branch")
        XCTAssertEqual(config.getBaseBranch(defaultBaseBranch: "main"), "feature/my-branch")
        
        // Verify to_dict also handles it correctly
        let result = config.toDict()
        XCTAssertEqual(result["baseBranch"] as? String, "feature/my-branch")
    }
    
    // MARK: - ProjectConfiguration Allowed Tools Tests
    
    func testFromYAMLStringParsesAllowedTools() throws {
        // Should parse allowedTools from YAML configuration
        // Arrange
        let project = Project(name: "my-project")
        let yamlContent = """
assignee: alice
allowedTools: Write,Read,Edit
"""
        
        // Act
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        
        // Assert
        XCTAssertEqual(config.allowedTools, "Write,Read,Edit")
    }
    
    func testFromYAMLStringAllowedToolsIsNoneWhenNotSpecified() throws {
        // Should have None allowed_tools when not specified in YAML
        // Arrange
        let project = Project(name: "my-project")
        let yamlContent = """
assignee: alice
"""
        
        // Act
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        
        // Assert
        XCTAssertNil(config.allowedTools)
    }
    
    func testGetAllowedToolsReturnsConfigValueWhenSet() throws {
        // Should return config's allowed_tools when it is set
        // Arrange
        let project = Project(name: "my-project")
        let config = ProjectConfiguration(project: project, allowedTools: "Write,Read,Edit")
        
        // Act
        let result = config.getAllowedTools(defaultAllowedTools: "Write,Read,Bash,Edit")
        
        // Assert
        XCTAssertEqual(result, "Write,Read,Edit")
    }
    
    func testGetAllowedToolsReturnsDefaultWhenNotSet() throws {
        // Should return default_allowed_tools when config's allowed_tools is not set
        // Arrange
        let project = Project(name: "my-project")
        let config = ProjectConfiguration(project: project, allowedTools: nil)
        
        // Act
        let result = config.getAllowedTools(defaultAllowedTools: "Write,Read,Bash,Edit")
        
        // Assert
        XCTAssertEqual(result, "Write,Read,Bash,Edit")
    }
    
    func testToDictIncludesAllowedToolsWhenSet() throws {
        // Should include allowedTools in dict when allowed_tools is set
        // Arrange
        let project = Project(name: "my-project")
        let config = ProjectConfiguration(project: project, allowedTools: "Write,Read,Edit")
        
        // Act
        let result = config.toDict()
        
        // Assert
        XCTAssertTrue(result.keys.contains("allowedTools"))
        XCTAssertEqual(result["allowedTools"] as? String, "Write,Read,Edit")
    }
    
    func testToDictExcludesAllowedToolsWhenNotSet() throws {
        // Should not include allowedTools in dict when allowed_tools is None
        // Arrange
        let project = Project(name: "my-project")
        let config = ProjectConfiguration(project: project, allowedTools: nil)
        
        // Act
        let result = config.toDict()
        
        // Assert
        XCTAssertFalse(result.keys.contains("allowedTools"))
    }
    
    // MARK: - ProjectConfiguration Stale PR Days Tests
    
    func testFromYAMLStringParsesStalePRDays() throws {
        // Should parse stalePRDays from YAML configuration
        // Arrange
        let project = Project(name: "my-project")
        let yamlContent = """
assignee: alice
stalePRDays: 14
"""
        
        // Act
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        
        // Assert
        XCTAssertEqual(config.stalePRDays, 14)
    }
    
    func testFromYAMLStringStalePRDaysIsNoneWhenNotSpecified() throws {
        // Should have None stale_pr_days when not specified in YAML
        // Arrange
        let project = Project(name: "my-project")
        let yamlContent = """
assignee: alice
"""
        
        // Act
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        
        // Assert
        XCTAssertNil(config.stalePRDays)
    }
    
    func testGetStalePRDaysReturnsConfigValueWhenSet() throws {
        // Should return config's stale_pr_days when it is set
        // Arrange
        let project = Project(name: "my-project")
        let config = ProjectConfiguration(project: project, stalePRDays: 14)
        
        // Act
        let result = config.getStalePRDays()
        
        // Assert
        XCTAssertEqual(result, 14)
    }
    
    func testGetStalePRDaysReturnsDefaultWhenNotSet() throws {
        // Should return default when config's stale_pr_days is not set
        // Arrange
        let project = Project(name: "my-project")
        let config = ProjectConfiguration(project: project, stalePRDays: nil)
        
        // Act
        let result = config.getStalePRDays()
        
        // Assert
        XCTAssertEqual(result, Constants.defaultStalePRDays)
    }
    
    func testGetStalePRDaysCustomDefault() throws {
        // Should use custom default when provided
        // Arrange
        let project = Project(name: "my-project")
        let config = ProjectConfiguration(project: project, stalePRDays: nil)
        
        // Act
        let result = config.getStalePRDays(defaultValue: 21)
        
        // Assert
        XCTAssertEqual(result, 21)
    }
    
    // MARK: - ProjectConfiguration Labels Tests
    
    func testFromYAMLStringParsesLabels() throws {
        // Should parse labels from YAML configuration
        // Arrange
        let project = Project(name: "my-project")
        let yamlContent = """
assignee: alice
labels: team-backend,needs-review
"""
        
        // Act
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        
        // Assert
        XCTAssertEqual(config.labels, "team-backend,needs-review")
    }
    
    func testFromYAMLStringLabelsIsNoneWhenNotSpecified() throws {
        // Should have None labels when not specified in YAML
        // Arrange
        let project = Project(name: "my-project")
        let yamlContent = """
assignee: alice
"""
        
        // Act
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        
        // Assert
        XCTAssertNil(config.labels)
    }
    
    func testGetLabelsReturnsConfigValueWhenSet() throws {
        // Should return config's labels when it is set
        // Arrange
        let project = Project(name: "my-project")
        let config = ProjectConfiguration(project: project, labels: "team-backend,needs-review")
        
        // Act
        let result = config.getLabels(defaultLabels: "default")
        
        // Assert
        XCTAssertEqual(result, "team-backend,needs-review")
    }
    
    func testGetLabelsReturnsDefaultWhenNotSet() throws {
        // Should return default_labels when config's labels is not set
        // Arrange
        let project = Project(name: "my-project")
        let config = ProjectConfiguration(project: project, labels: nil)
        
        // Act
        let result = config.getLabels(defaultLabels: "default")
        
        // Assert
        XCTAssertEqual(result, "default")
    }
    
    // MARK: - Full Configuration Integration Tests
    
    func testComplexYAMLConfiguration() throws {
        // Should parse all configuration fields correctly
        // Arrange
        let project = Project(name: "full-config-test")
        let yamlContent = """
assignee: alice
baseBranch: develop
allowedTools: Read,Write,Edit,Bash(npm test:*)
stalePRDays: 14
labels: team-backend,needs-review
"""
        
        // Act
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        
        // Assert
        XCTAssertEqual(config.project.name, "full-config-test")
        XCTAssertEqual(config.assignees, ["alice"])
        XCTAssertEqual(config.baseBranch, "develop")
        XCTAssertEqual(config.allowedTools, "Read,Write,Edit,Bash(npm test:*)")
        XCTAssertEqual(config.stalePRDays, 14)
        XCTAssertEqual(config.labels, "team-backend,needs-review")
        
        // Verify all getters work correctly
        XCTAssertEqual(config.getBaseBranch(defaultBaseBranch: "main"), "develop")
        XCTAssertEqual(config.getAllowedTools(defaultAllowedTools: "Write,Read,Bash,Edit"), "Read,Write,Edit,Bash(npm test:*)")
        XCTAssertEqual(config.getStalePRDays(), 14)
        XCTAssertEqual(config.getLabels(defaultLabels: "default"), "team-backend,needs-review")
        
        // Verify to_dict includes all fields
        let result = config.toDict()
        XCTAssertEqual(result["assignees"] as? [String], ["alice"])
        XCTAssertEqual(result["baseBranch"] as? String, "develop")
        XCTAssertEqual(result["allowedTools"] as? String, "Read,Write,Edit,Bash(npm test:*)")
        XCTAssertEqual(result["stalePRDays"] as? Int, 14)
        XCTAssertEqual(result["labels"] as? String, "team-backend,needs-review")
    }
    
    // MARK: - Assignees and Reviewers Tests
    
    func testAssigneesListFromYAML() throws {
        // Should parse assignees list from YAML
        let project = Project(name: "my-project")
        let yamlContent = """
assignees:
  - alice
  - bob
"""
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        
        XCTAssertEqual(config.assignees, ["alice", "bob"])
    }
    
    func testAssigneeSingularBackwardCompat() throws {
        // Legacy singular assignee in YAML should be folded into assignees list
        let project = Project(name: "my-project")
        let yamlContent = """
assignee: alice
"""
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        
        XCTAssertEqual(config.assignees, ["alice"])
    }
    
    func testAssigneesOverridesSingularAssignee() throws {
        // assignees list takes precedence over legacy assignee field
        let project = Project(name: "my-project")
        let yamlContent = """
assignee: alice
assignees:
  - bob
  - carol
"""
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        
        XCTAssertEqual(config.assignees, ["bob", "carol"])
    }
    
    func testReviewersListFromYAML() throws {
        // Should parse reviewers list from YAML
        let project = Project(name: "my-project")
        let yamlContent = """
reviewers:
  - charlie
  - dave
"""
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        
        XCTAssertEqual(config.reviewers, ["charlie", "dave"])
    }
    
    func testReviewersStringFromYAML() throws {
        // Should handle reviewers as a plain string (not a list)
        let project = Project(name: "my-project")
        let yamlContent = """
reviewers: smorris_jepp
"""
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        
        XCTAssertEqual(config.reviewers, ["smorris_jepp"])
    }
    
    func testAssigneesStringFromYAML() throws {
        // Should handle assignees as a plain string (not a list)
        let project = Project(name: "my-project")
        let yamlContent = """
assignees: alice
"""
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        
        XCTAssertEqual(config.assignees, ["alice"])
    }
    
    func testNoAssigneesReturnsEmptyList() throws {
        // Should return [] when no assignee configured
        let project = Project(name: "my-project")
        let config = ProjectConfiguration.default(project: project)
        
        XCTAssertEqual(config.assignees, [] as [String])
    }
    
    func testNoReviewersReturnsEmptyList() throws {
        // Should return [] when no reviewers configured
        let project = Project(name: "my-project")
        let config = ProjectConfiguration.default(project: project)
        
        XCTAssertEqual(config.reviewers, [] as [String])
    }
    
    func testToDictIncludesAssignees() throws {
        // to_dict() should include assignees when set
        let project = Project(name: "my-project")
        let config = ProjectConfiguration(project: project, assignees: ["alice", "bob"])
        
        let result = config.toDict()
        
        XCTAssertEqual(result["assignees"] as? [String], ["alice", "bob"])
    }
    
    func testToDictIncludesReviewers() throws {
        // to_dict() should include reviewers when set
        let project = Project(name: "my-project")
        let config = ProjectConfiguration(project: project, reviewers: ["charlie"])
        
        let result = config.toDict()
        
        XCTAssertEqual(result["reviewers"] as? [String], ["charlie"])
    }
}