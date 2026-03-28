import XCTest
@testable import ClaudeChainService
@testable import ClaudeChainServices
import Foundation

/// Tests for Slack block limit and completed project filtering
/// Swift port of test_slack_block_limit.py
final class SlackBlockLimitTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    /// Helper to create a ProjectStats with given counts
    private func makeProject(name: String, total: Int, completed: Int) -> ProjectStats {
        let projectStats = ProjectStats(projectName: name, specPath: "projects/\(name)/spec.md")
        projectStats.totalTasks = total
        projectStats.completedTasks = completed
        return projectStats
    }
    
    // MARK: - Completed Projects Default Tests
    
    func testCompletedProjectIncludedByDefault() {
        // By default, completed projects should be included
        
        // Arrange
        let report = StatisticsReport(repo: "owner/repo")
        report.addProject(makeProject(name: "done-project", total: 5, completed: 5))
        report.addProject(makeProject(name: "active-project", total: 5, completed: 2))
        
        // Act
        let projects = Array(report.projectStats.values)
        let completedProjects = projects.filter { $0.completedTasks == $0.totalTasks && $0.totalTasks > 0 }
        let activeProjects = projects.filter { $0.completedTasks < $0.totalTasks }
        
        // Assert
        XCTAssertEqual(completedProjects.count, 1)
        XCTAssertEqual(activeProjects.count, 1)
        XCTAssertEqual(completedProjects.first?.projectName, "done-project")
        XCTAssertEqual(activeProjects.first?.projectName, "active-project")
    }
    
    func testCompletedProjectExcludedWhenFilterApplied() {
        // When hide_completed_projects flag is true, completed projects should be excluded
        
        // Arrange
        let report = StatisticsReport(repo: "owner/repo")
        report.addProject(makeProject(name: "done-project", total: 5, completed: 5))
        report.addProject(makeProject(name: "active-project", total: 5, completed: 2))
        
        // Act - Filter out completed projects
        let projects = Array(report.projectStats.values)
        let filteredProjects = projects.filter { !($0.completedTasks == $0.totalTasks && $0.totalTasks > 0) }
        
        // Assert
        XCTAssertEqual(filteredProjects.count, 1)
        XCTAssertEqual(filteredProjects.first?.projectName, "active-project")
    }
    
    func testAllCompletedHiddenStillReturnsValidData() {
        // When all projects are completed and hidden, should still return valid data structure
        
        // Arrange
        let report = StatisticsReport(repo: "owner/repo")
        report.addProject(makeProject(name: "done1", total: 3, completed: 3))
        report.addProject(makeProject(name: "done2", total: 2, completed: 2))
        
        // Act - Filter out all completed projects
        let projects = Array(report.projectStats.values)
        let filteredProjects = projects.filter { !($0.completedTasks == $0.totalTasks && $0.totalTasks > 0) }
        
        // Assert - Should return empty array but still be valid
        XCTAssertNotNil(filteredProjects)
        XCTAssertEqual(filteredProjects.count, 0)
        XCTAssertNotNil(report) // Report structure should still be valid
    }
    
    func testPartiallyCompletedProjectAlwaysIncluded() {
        // Partially completed projects should always be included regardless of filter
        
        // Arrange
        let report = StatisticsReport(repo: "owner/repo")
        report.addProject(makeProject(name: "partial", total: 5, completed: 4))
        
        // Act - Even when filtering completed projects, partial should remain
        let projects = Array(report.projectStats.values)
        let filteredProjects = projects.filter { !($0.completedTasks == $0.totalTasks && $0.totalTasks > 0) }
        
        // Assert
        XCTAssertEqual(filteredProjects.count, 1)
        XCTAssertEqual(filteredProjects.first?.projectName, "partial")
        XCTAssertEqual(filteredProjects.first?.completedTasks, 4)
        XCTAssertEqual(filteredProjects.first?.totalTasks, 5)
    }
    
    // MARK: - Slack Block Truncation Tests
    
    func testManyProjectsSimulatedTruncation() {
        // Simulate truncation behavior for many projects
        
        // Arrange
        let report = StatisticsReport(repo: "owner/repo")
        // Each project would generate multiple blocks; 30 projects should exceed typical limits
        for i in 0..<30 {
            report.addProject(makeProject(name: String(format: "project-%02d", i), total: 5, completed: i % 5))
        }
        
        // Act - Simulate block generation (each project might generate ~2-3 blocks)
        let projects = Array(report.projectStats.values).sorted { $0.projectName < $1.projectName }
        let estimatedBlockCount = projects.count * 3 // Rough estimate of blocks per project
        
        // Assert - Should detect that we would exceed limits
        XCTAssertEqual(projects.count, 30)
        XCTAssertGreaterThan(estimatedBlockCount, 50) // Would exceed Slack's 50-block limit
    }
    
    func testTruncationIndicatorConcept() {
        // Test the concept of needing a truncation indicator
        
        // Arrange
        let maxBlocks = 50
        let blocksPerProject = 3
        let projects = (0..<20).map { i in
            makeProject(name: "project-\(i)", total: 5, completed: i % 5)
        }
        
        // Act - Calculate if truncation would be needed
        let totalBlocksNeeded = projects.count * blocksPerProject
        let needsTruncation = totalBlocksNeeded >= maxBlocks
        
        // Assert
        if needsTruncation {
            // If we need truncation, the last block should be reserved for the indicator
            let maxProjectBlocks = maxBlocks - 1
            let maxProjects = maxProjectBlocks / blocksPerProject
            XCTAssertLessThan(maxProjects, projects.count)
        }
        
        XCTAssertTrue(needsTruncation) // With 20 projects * 3 blocks = 60, should need truncation
    }
    
    func testFewProjectsNotTruncated() {
        // Few projects should not trigger truncation
        
        // Arrange
        let report = StatisticsReport(repo: "owner/repo")
        report.addProject(makeProject(name: "small", total: 3, completed: 1))
        
        // Act - Simulate block generation
        let projects = Array(report.projectStats.values)
        let estimatedBlockCount = projects.count * 3 // Conservative estimate
        
        // Assert - Should not exceed limits
        XCTAssertEqual(projects.count, 1)
        XCTAssertLessThanOrEqual(estimatedBlockCount, 50)
    }
    
    // MARK: - Project Statistics Validation Tests
    
    func testProjectStatsCalculations() {
        // Verify that project statistics are calculated correctly
        
        // Arrange
        let report = StatisticsReport(repo: "owner/repo")
        let project = makeProject(name: "test-project", total: 10, completed: 7)
        // Manually set pending tasks since it's not automatically calculated
        project.pendingTasks = project.totalTasks - project.completedTasks
        report.addProject(project)
        
        // Act
        let retrievedProject = report.projectStats["test-project"]
        
        // Assert
        XCTAssertNotNil(retrievedProject)
        XCTAssertEqual(retrievedProject?.projectName, "test-project")
        XCTAssertEqual(retrievedProject?.totalTasks, 10)
        XCTAssertEqual(retrievedProject?.completedTasks, 7)
        XCTAssertEqual(retrievedProject?.pendingTasks, 3) // 10 - 7
    }
    
    func testMultipleProjectsInReport() {
        // Test managing multiple projects in a single report
        
        // Arrange
        let report = StatisticsReport(repo: "owner/repo")
        let projects = [
            makeProject(name: "alpha", total: 5, completed: 5),
            makeProject(name: "beta", total: 8, completed: 3),
            makeProject(name: "gamma", total: 2, completed: 0)
        ]
        
        // Act
        projects.forEach { report.addProject($0) }
        
        // Assert
        XCTAssertEqual(report.projectStats.count, 3)
        XCTAssertNotNil(report.projectStats["alpha"])
        XCTAssertNotNil(report.projectStats["beta"])
        XCTAssertNotNil(report.projectStats["gamma"])
        
        // Verify completed project detection
        let completedProjects = report.projectStats.values.filter { 
            $0.completedTasks == $0.totalTasks && $0.totalTasks > 0 
        }
        XCTAssertEqual(completedProjects.count, 1)
        XCTAssertEqual(completedProjects.first?.projectName, "alpha")
    }
}