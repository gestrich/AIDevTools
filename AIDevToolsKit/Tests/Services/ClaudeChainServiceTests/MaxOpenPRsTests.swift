/// Tests for maxOpenPRs configuration and capacity checking
import XCTest
import Foundation
@testable import ClaudeChainService

class MaxOpenPRsTests: XCTestCase {
    
    // MARK: - ProjectConfiguration MaxOpenPRs Tests
    
    func testDefaultMaxOpenPRsIsNone() throws {
        // Should default to None when not specified
        let project = Project(name: "test-project")
        let config = ProjectConfiguration.default(project: project)
        XCTAssertNil(config.maxOpenPRs)
    }
    
    func testGetMaxOpenPRsReturnsDefaultWhenNotSet() throws {
        // Should return default of 1 when not configured
        let project = Project(name: "test-project")
        let config = ProjectConfiguration.default(project: project)
        XCTAssertEqual(config.getMaxOpenPRs(), 1)
    }
    
    func testGetMaxOpenPRsReturnsConfiguredValue() throws {
        // Should return configured value when set
        let project = Project(name: "test-project")
        let config = ProjectConfiguration(project: project, maxOpenPRs: 3)
        XCTAssertEqual(config.getMaxOpenPRs(), 3)
    }
    
    func testGetMaxOpenPRsCustomDefault() throws {
        // Should use custom default when not configured
        let project = Project(name: "test-project")
        let config = ProjectConfiguration.default(project: project)
        XCTAssertEqual(config.getMaxOpenPRs(defaultValue: 5), 5)
    }
    
    func testFromYAMLStringWithMaxOpenPRs() throws {
        // Should parse maxOpenPRs from YAML configuration
        let project = Project(name: "test-project")
        let yamlContent = """
assignee: alice
maxOpenPRs: 3
"""
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        XCTAssertEqual(config.maxOpenPRs, 3)
        XCTAssertEqual(config.getMaxOpenPRs(), 3)
    }
    
    func testFromYAMLStringWithoutMaxOpenPRs() throws {
        // Should have None maxOpenPRs when not specified in YAML
        let project = Project(name: "test-project")
        let yamlContent = """
assignee: alice
"""
        let config = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: yamlContent)
        XCTAssertNil(config.maxOpenPRs)
        XCTAssertEqual(config.getMaxOpenPRs(), 1)
    }
    
    func testToDictIncludesMaxOpenPRs() throws {
        // Should include maxOpenPRs in dict when set
        let project = Project(name: "test-project")
        let config = ProjectConfiguration(project: project, maxOpenPRs: 3)
        let result = config.toDict()
        XCTAssertEqual(result["maxOpenPRs"] as? Int, 3)
    }
    
    func testToDictExcludesMaxOpenPRsWhenNone() throws {
        // Should not include maxOpenPRs in dict when not set
        let project = Project(name: "test-project")
        let config = ProjectConfiguration.default(project: project)
        let result = config.toDict()
        XCTAssertNil(result["maxOpenPRs"])
    }
    
    // MARK: - CapacityResult MaxOpenPRs Tests
    
    func testDefaultMaxOpenPRsIsOne() throws {
        // Should default max_open_prs to 1
        let result = CapacityResult(
            hasCapacity: true,
            openPRs: [],
            projectName: "test"
        )
        XCTAssertEqual(result.maxOpenPRs, 1)
    }
    
    func testFormatSummaryShowsConfiguredMax() throws {
        // Should display configured max in summary
        let prInfo = ["pr_number": 1, "task_description": "task"] as [String: Any]
        let result = CapacityResult(
            hasCapacity: true,
            openPRs: [prInfo],
            projectName: "test",
            maxOpenPRs: 3,
            assignees: ["alice"]
        )
        let summary = result.formatSummary()
        XCTAssertTrue(summary.contains("**Max PRs Allowed:** 3"))
        XCTAssertTrue(summary.contains("**Currently Open:** 1/3"))
    }
    
    func testFormatSummaryShowsDefaultMax() throws {
        // Should display default max of 1 in summary
        let prInfo = ["pr_number": 1, "task_description": "task"] as [String: Any]
        let result = CapacityResult(
            hasCapacity: false,
            openPRs: [prInfo],
            projectName: "test"
        )
        let summary = result.formatSummary()
        XCTAssertTrue(summary.contains("**Max PRs Allowed:** 1"))
        XCTAssertTrue(summary.contains("**Currently Open:** 1/1"))
    }
}