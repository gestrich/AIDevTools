/// Unit tests for configuration loading and validation
import XCTest
import Foundation
@testable import ClaudeChainService

final class TestLoadConfig: XCTestCase {
    /// Test suite for YAML configuration loading
    
    func testLoadValidConfigFile() throws {
        /// Should load and parse valid YAML configuration
        let tempDir = FileManager.default.temporaryDirectory
        let configFile = tempDir.appendingPathComponent("config_\(UUID()).yml")
        
        let configContent = """
reviewers:
  - username: alice
    maxOpenPRs: 2
  - username: bob
    maxOpenPRs: 3
"""
        try configContent.write(to: configFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configFile) }
        
        // Act
        let config = try Config.loadConfig(filePath: configFile.path)
        
        // Assert
        XCTAssertTrue(config.keys.contains("reviewers"))
        let reviewers = config["reviewers"] as? [[String: Any]]
        XCTAssertNotNil(reviewers)
        XCTAssertEqual(reviewers?.count, 2)
        XCTAssertEqual(reviewers?[0]["username"] as? String, "alice")
        XCTAssertEqual(reviewers?[0]["maxOpenPRs"] as? Int, 2)
    }
    
    func testLoadConfigRaisesErrorWhenFileNotFound() throws {
        /// Should raise FileNotFoundError when config file doesn't exist
        let tempDir = FileManager.default.temporaryDirectory
        let missingFile = tempDir.appendingPathComponent("missing_\(UUID()).yml")
        
        XCTAssertThrowsError(try Config.loadConfig(filePath: missingFile.path)) { error in
            XCTAssertTrue(error is FileNotFoundError)
            if let fileError = error as? FileNotFoundError {
                XCTAssertTrue(fileError.message.contains("File not found"))
            }
        }
    }
    
    func testLoadConfigRaisesErrorForInvalidYAML() throws {
        /// Should raise ConfigurationError for malformed YAML
        let tempDir = FileManager.default.temporaryDirectory
        let configFile = tempDir.appendingPathComponent("bad_config_\(UUID()).yml")
        
        let badConfigContent = """
reviewers:
  - username: alice
    invalid yaml syntax here: [missing bracket
"""
        try badConfigContent.write(to: configFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configFile) }
        
        XCTAssertThrowsError(try Config.loadConfig(filePath: configFile.path)) { error in
            XCTAssertTrue(error is ConfigurationError)
            if let configError = error as? ConfigurationError {
                XCTAssertTrue(configError.message.contains("Invalid YAML"))
            }
        }
    }
    
    func testLoadConfigRejectsDeprecatedBranchPrefix() throws {
        /// Should reject configuration with deprecated branchPrefix field
        let tempDir = FileManager.default.temporaryDirectory
        let configFile = tempDir.appendingPathComponent("config_\(UUID()).yml")
        
        let configContent = """
branchPrefix: custom-prefix
reviewers:
  - username: alice
    maxOpenPRs: 2
"""
        try configContent.write(to: configFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configFile) }
        
        XCTAssertThrowsError(try Config.loadConfig(filePath: configFile.path)) { error in
            XCTAssertTrue(error is ConfigurationError)
            if let configError = error as? ConfigurationError {
                XCTAssertTrue(configError.message.contains("'branchPrefix' field is no longer supported"))
            }
        }
    }
    
    func testLoadConfigErrorMessageExplainsBranchPrefixRemoval() throws {
        /// Should provide helpful error message about branchPrefix removal
        let tempDir = FileManager.default.temporaryDirectory
        let configFile = tempDir.appendingPathComponent("config_\(UUID()).yml")
        
        let configContent = """
branchPrefix: custom
reviewers: []
"""
        try configContent.write(to: configFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configFile) }
        
        XCTAssertThrowsError(try Config.loadConfig(filePath: configFile.path)) { error in
            XCTAssertTrue(error is ConfigurationError)
            if let configError = error as? ConfigurationError {
                XCTAssertTrue(configError.message.contains("claude-chain-{project}-{index}"))
            }
        }
    }
    
    func testLoadConfigAcceptsEmptyReviewersList() throws {
        /// Should load config with empty reviewers list (validation happens elsewhere)
        let tempDir = FileManager.default.temporaryDirectory
        let configFile = tempDir.appendingPathComponent("config_\(UUID()).yml")
        
        let configContent = """
reviewers: []
"""
        try configContent.write(to: configFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configFile) }
        
        // Act
        let config = try Config.loadConfig(filePath: configFile.path)
        
        // Assert
        XCTAssertTrue(config.keys.contains("reviewers"))
        let reviewers = config["reviewers"] as? [Any]
        XCTAssertNotNil(reviewers)
        XCTAssertEqual(reviewers?.count, 0)
    }
    
    func testLoadConfigWithAdditionalFields() throws {
        /// Should preserve additional configuration fields
        let tempDir = FileManager.default.temporaryDirectory
        let configFile = tempDir.appendingPathComponent("config_\(UUID()).yml")
        
        let configContent = """
reviewers:
  - username: alice
    maxOpenPRs: 2
slackWebhook: https://hooks.slack.com/services/xxx
customField: customValue
"""
        try configContent.write(to: configFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configFile) }
        
        // Act
        let config = try Config.loadConfig(filePath: configFile.path)
        
        // Assert
        XCTAssertEqual(config["slackWebhook"] as? String, "https://hooks.slack.com/services/xxx")
        XCTAssertEqual(config["customField"] as? String, "customValue")
    }
}

final class TestSubstituteTemplate: XCTestCase {
    /// Test suite for template variable substitution
    
    func testSubstituteSingleVariable() {
        /// Should substitute a single variable in template
        let template = "Hello {{NAME}}"
        
        let result = Config.substituteTemplate(template, variables: ["NAME": "Alice"])
        
        XCTAssertEqual(result, "Hello Alice")
    }
    
    func testSubstituteMultipleVariables() {
        /// Should substitute multiple variables in template
        let template = "Project: {{PROJECT}}, Task: {{TASK_ID}}"
        
        let result = Config.substituteTemplate(template, variables: [
            "PROJECT": "my-project",
            "TASK_ID": "5"
        ])
        
        XCTAssertEqual(result, "Project: my-project, Task: 5")
    }
    
    func testSubstituteVariableMultipleTimes() {
        /// Should substitute the same variable appearing multiple times
        let template = "{{NAME}} is working on {{NAME}}'s task"
        
        let result = Config.substituteTemplate(template, variables: ["NAME": "Alice"])
        
        XCTAssertEqual(result, "Alice is working on Alice's task")
    }
    
    func testSubstituteWithNoVariables() {
        /// Should return template unchanged when no variables provided
        let template = "Static text without variables"
        
        let result = Config.substituteTemplate(template, variables: [:])
        
        XCTAssertEqual(result, "Static text without variables")
    }
    
    func testSubstituteLeavesUnknownVariablesUnchanged() {
        /// Should leave placeholders unchanged if variable not provided
        let template = "Hello {{NAME}}, your task is {{TASK_ID}}"
        
        let result = Config.substituteTemplate(template, variables: ["NAME": "Alice"])
        
        XCTAssertEqual(result, "Hello Alice, your task is {{TASK_ID}}")
    }
    
    func testSubstituteWithNumericValues() {
        /// Should convert numeric values to strings during substitution
        let template = "Task {{INDEX}} of {{TOTAL}}"
        
        let result = Config.substituteTemplate(template, variables: [
            "INDEX": 5,
            "TOTAL": 10
        ])
        
        XCTAssertEqual(result, "Task 5 of 10")
    }
    
    func testSubstituteWithEmptyString() {
        /// Should substitute empty string values
        let template = "Value: {{VAR}}"
        
        let result = Config.substituteTemplate(template, variables: ["VAR": ""])
        
        XCTAssertEqual(result, "Value: ")
    }
    
    func testSubstitutePreservesMultilineTemplates() {
        /// Should preserve newlines in multiline templates
        let template = """
Line 1: {{VAR1}}
Line 2: {{VAR2}}
Line 3: {{VAR3}}
"""
        
        let result = Config.substituteTemplate(template, variables: [
            "VAR1": "A",
            "VAR2": "B",
            "VAR3": "C"
        ])
        
        let expected = """
Line 1: A
Line 2: B
Line 3: C
"""
        XCTAssertEqual(result, expected)
    }
}

final class TestValidateSpecFormat: XCTestCase {
    /// Test suite for spec.md format validation
    
    func testValidateSpecWithUncheckedTasks() throws {
        /// Should validate spec file with unchecked tasks
        let tempDir = FileManager.default.temporaryDirectory
        let specFile = tempDir.appendingPathComponent("spec_\(UUID()).md")
        
        let specContent = """
# Project Tasks

- [ ] Task 1
- [ ] Task 2
- [ ] Task 3
"""
        try specContent.write(to: specFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: specFile) }
        
        // Act
        let result = try Config.validateSpecFormat(specFile: specFile.path)
        
        // Assert
        XCTAssertTrue(result)
    }
    
    func testValidateSpecWithCheckedTasks() throws {
        /// Should validate spec file with checked tasks
        let tempDir = FileManager.default.temporaryDirectory
        let specFile = tempDir.appendingPathComponent("spec_\(UUID()).md")
        
        let specContent = """
# Project Tasks

- [x] Completed task
- [X] Also completed (capital X)
- [ ] Pending task
"""
        try specContent.write(to: specFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: specFile) }
        
        // Act
        let result = try Config.validateSpecFormat(specFile: specFile.path)
        
        // Assert
        XCTAssertTrue(result)
    }
    
    func testValidateSpecWithMixedTasks() throws {
        /// Should validate spec file with mix of checked and unchecked tasks
        let tempDir = FileManager.default.temporaryDirectory
        let specFile = tempDir.appendingPathComponent("spec_\(UUID()).md")
        
        let specContent = """
- [x] Done
- [ ] Not done
"""
        try specContent.write(to: specFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: specFile) }
        
        // Act
        let result = try Config.validateSpecFormat(specFile: specFile.path)
        
        // Assert
        XCTAssertTrue(result)
    }
    
    func testValidateSpecRaisesErrorWhenFileNotFound() throws {
        /// Should raise FileNotFoundError when spec file doesn't exist
        let tempDir = FileManager.default.temporaryDirectory
        let missingFile = tempDir.appendingPathComponent("missing_spec_\(UUID()).md")
        
        XCTAssertThrowsError(try Config.validateSpecFormat(specFile: missingFile.path)) { error in
            XCTAssertTrue(error is FileNotFoundError)
            if let fileError = error as? FileNotFoundError {
                XCTAssertTrue(fileError.message.contains("Spec file not found"))
            }
        }
    }
    
    func testValidateSpecRaisesErrorForNoChecklistItems() throws {
        /// Should raise ConfigurationError when no checklist items found
        let tempDir = FileManager.default.temporaryDirectory
        let specFile = tempDir.appendingPathComponent("spec_\(UUID()).md")
        
        let specContent = """
# Project

This is just some text without any checklist items.
"""
        try specContent.write(to: specFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: specFile) }
        
        XCTAssertThrowsError(try Config.validateSpecFormat(specFile: specFile.path)) { error in
            XCTAssertTrue(error is ConfigurationError)
            if let configError = error as? ConfigurationError {
                XCTAssertTrue(configError.message.contains("No checklist items found"))
            }
        }
    }
    
    func testValidateSpecErrorExplainsRequiredFormat() throws {
        /// Should explain required format in error message
        let tempDir = FileManager.default.temporaryDirectory
        let specFile = tempDir.appendingPathComponent("spec_\(UUID()).md")
        
        let specContent = "No tasks here"
        try specContent.write(to: specFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: specFile) }
        
        XCTAssertThrowsError(try Config.validateSpecFormat(specFile: specFile.path)) { error in
            XCTAssertTrue(error is ConfigurationError)
            if let configError = error as? ConfigurationError {
                XCTAssertTrue(configError.message.contains("- [ ]") || configError.message.contains("- [x]"))
            }
        }
    }
    
    func testValidateSpecWithIndentedTasks() throws {
        /// Should validate indented checklist items
        let tempDir = FileManager.default.temporaryDirectory
        let specFile = tempDir.appendingPathComponent("spec_\(UUID()).md")
        
        let specContent = """
# Tasks

  - [ ] Indented task 1
    - [ ] Nested task
  - [x] Completed indented task
"""
        try specContent.write(to: specFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: specFile) }
        
        // Act
        let result = try Config.validateSpecFormat(specFile: specFile.path)
        
        // Assert
        XCTAssertTrue(result)
    }
    
    func testValidateSpecIgnoresNonChecklistBullets() throws {
        /// Should ignore regular bullet points that aren't checklist items
        let tempDir = FileManager.default.temporaryDirectory
        let specFile = tempDir.appendingPathComponent("spec_\(UUID()).md")
        
        let specContent = """
# Notes

- This is a regular bullet point
- Another regular bullet

# Tasks

- [ ] This is a checklist item
"""
        try specContent.write(to: specFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: specFile) }
        
        // Act
        let result = try Config.validateSpecFormat(specFile: specFile.path)
        
        // Assert
        XCTAssertTrue(result)
    }
    
    func testValidateSpecWithTaskAtStartOfLine() throws {
        /// Should match tasks at the start of line without indentation
        let tempDir = FileManager.default.temporaryDirectory
        let specFile = tempDir.appendingPathComponent("spec_\(UUID()).md")
        
        let specContent = "- [ ] Task without indentation"
        try specContent.write(to: specFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: specFile) }
        
        // Act
        let result = try Config.validateSpecFormat(specFile: specFile.path)
        
        // Assert
        XCTAssertTrue(result)
    }
    
    func testValidateSpecWithWhitespaceVariations() throws {
        /// Should handle various whitespace patterns in checklist items
        let tempDir = FileManager.default.temporaryDirectory
        let specFile = tempDir.appendingPathComponent("spec_\(UUID()).md")
        
        let specContent = """
- [ ] Normal spacing
-  [ ]  Extra spaces
-   [x]   Many spaces
"""
        try specContent.write(to: specFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: specFile) }
        
        // Act
        let result = try Config.validateSpecFormat(specFile: specFile.path)
        
        // Assert
        XCTAssertTrue(result)
    }
    
    func testValidateSpecWithEmptyFile() throws {
        /// Should raise error for empty spec file
        let tempDir = FileManager.default.temporaryDirectory
        let specFile = tempDir.appendingPathComponent("spec_\(UUID()).md")
        
        let specContent = ""
        try specContent.write(to: specFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: specFile) }
        
        XCTAssertThrowsError(try Config.validateSpecFormat(specFile: specFile.path)) { error in
            XCTAssertTrue(error is ConfigurationError)
            if let configError = error as? ConfigurationError {
                XCTAssertTrue(configError.message.contains("No checklist items found"))
            }
        }
    }
}