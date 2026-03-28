/// Test suite for TaskStatus and TaskWithPR domain models
import XCTest
import Foundation
@testable import ClaudeChainService

class TaskWithPRTests: XCTestCase {
    
    // MARK: - PRState Tests
    
    func testOpenStateValue() throws {
        // Should have correct value for OPEN state
        XCTAssertEqual(PRState.open.rawValue, "open")
    }
    
    func testClosedStateValue() throws {
        // Should have correct value for CLOSED state
        XCTAssertEqual(PRState.closed.rawValue, "closed")
    }
    
    func testMergedStateValue() throws {
        // Should have correct value for MERGED state
        XCTAssertEqual(PRState.merged.rawValue, "merged")
    }
    
    func testFromStringOpen() throws {
        // Should parse 'open' string to OPEN state
        XCTAssertEqual(try PRState.fromString("open"), PRState.open)
        XCTAssertEqual(try PRState.fromString("OPEN"), PRState.open)
    }
    
    func testFromStringClosed() throws {
        // Should parse 'closed' string to CLOSED state
        XCTAssertEqual(try PRState.fromString("closed"), PRState.closed)
        XCTAssertEqual(try PRState.fromString("CLOSED"), PRState.closed)
    }
    
    func testFromStringMerged() throws {
        // Should parse 'merged' string to MERGED state
        XCTAssertEqual(try PRState.fromString("merged"), PRState.merged)
        XCTAssertEqual(try PRState.fromString("MERGED"), PRState.merged)
    }
    
    func testFromStringInvalidRaisesError() throws {
        // Should raise error for invalid state string
        XCTAssertThrowsError(try PRState.fromString("invalid")) { error in
            if let configError = error as? ConfigurationError {
                XCTAssertTrue(configError.message.contains("Invalid PR state"))
            } else {
                XCTFail("Expected ConfigurationError, got \(type(of: error))")
            }
        }
    }
    
    // MARK: - TaskStatus Tests
    
    func testPendingStatusValue() throws {
        // Should have correct value for PENDING status
        XCTAssertEqual(TaskStatus.pending.rawValue, "pending")
    }
    
    func testInProgressStatusValue() throws {
        // Should have correct value for IN_PROGRESS status
        XCTAssertEqual(TaskStatus.inProgress.rawValue, "in_progress")
    }
    
    func testCompletedStatusValue() throws {
        // Should have correct value for COMPLETED status
        XCTAssertEqual(TaskStatus.completed.rawValue, "completed")
    }
    
    func testAllStatusesAreDistinct() throws {
        // Should have three distinct status values
        let statuses = [TaskStatus.pending, TaskStatus.inProgress, TaskStatus.completed]
        XCTAssertEqual(statuses.count, 3)
        
        let values = Set(statuses.map { $0.rawValue })
        XCTAssertEqual(values.count, 3)
    }
    
    // MARK: - TaskWithPR Tests
    
    private func makeSamplePR() -> GitHubPullRequest {
        // Create a sample GitHubPullRequest for testing
        return GitHubPullRequest(
            number: 42,
            title: "ClaudeChain: Add user authentication",
            state: "open",
            createdAt: Date(timeIntervalSince1970: 1672574400), // 2023-01-01 12:00:00 UTC
            mergedAt: nil,
            assignees: [GitHubUser(login: "alice")],
            labels: ["claudechain"],
            headRefName: "claude-chain-my-project-a3f2b891"
        )
    }
    
    private func makeMergedPR() -> GitHubPullRequest {
        // Create a merged GitHubPullRequest for testing
        return GitHubPullRequest(
            number: 41,
            title: "ClaudeChain: Add input validation",
            state: "merged",
            createdAt: Date(timeIntervalSince1970: 1672567200), // 2023-01-01 10:00:00 UTC
            mergedAt: Date(timeIntervalSince1970: 1672675200), // 2023-01-02 16:00:00 UTC
            assignees: [GitHubUser(login: "bob")],
            labels: ["claudechain"],
            headRefName: "claude-chain-my-project-b4c3d2e1"
        )
    }
    
    func testTaskWithPRCreation() throws {
        // Should create TaskWithPR with all required fields
        let samplePR = makeSamplePR()
        let task = TaskWithPR(
            taskHash: "a3f2b891",
            description: "Add user authentication",
            status: .inProgress,
            pr: samplePR
        )
        
        XCTAssertEqual(task.taskHash, "a3f2b891")
        XCTAssertEqual(task.description, "Add user authentication")
        XCTAssertEqual(task.status, .inProgress)
        XCTAssertEqual(task.pr, samplePR)
    }
    
    func testTaskWithoutPR() throws {
        // Should create TaskWithPR without PR (pending task)
        let task = TaskWithPR(
            taskHash: "c5d4e3f2",
            description: "Add logging",
            status: .pending,
            pr: nil
        )
        
        XCTAssertEqual(task.taskHash, "c5d4e3f2")
        XCTAssertEqual(task.description, "Add logging")
        XCTAssertEqual(task.status, .pending)
        XCTAssertNil(task.pr)
    }
    
    func testHasPRReturnsTrueWhenPRExists() throws {
        // Should return True for hasPR when PR is assigned
        let samplePR = makeSamplePR()
        let task = TaskWithPR(
            taskHash: "a3f2b891",
            description: "Add user authentication",
            status: .inProgress,
            pr: samplePR
        )
        
        XCTAssertTrue(task.hasPR)
    }
    
    func testHasPRReturnsFalseWhenNoPR() throws {
        // Should return False for hasPR when PR is None
        let task = TaskWithPR(
            taskHash: "c5d4e3f2",
            description: "Add logging",
            status: .pending,
            pr: nil
        )
        
        XCTAssertFalse(task.hasPR)
    }
    
    func testPRNumberReturnsNumberWhenPRExists() throws {
        // Should return PR number when PR is assigned
        let samplePR = makeSamplePR()
        let task = TaskWithPR(
            taskHash: "a3f2b891",
            description: "Add user authentication",
            status: .inProgress,
            pr: samplePR
        )
        
        XCTAssertEqual(task.prNumber, 42)
    }
    
    func testPRNumberReturnsNoneWhenNoPR() throws {
        // Should return None for prNumber when PR is None
        let task = TaskWithPR(
            taskHash: "c5d4e3f2",
            description: "Add logging",
            status: .pending,
            pr: nil
        )
        
        XCTAssertNil(task.prNumber)
    }
    
    func testPRStateReturnsStateWhenPRExists() throws {
        // Should return PR state when PR is assigned
        let samplePR = makeSamplePR()
        let task = TaskWithPR(
            taskHash: "a3f2b891",
            description: "Add user authentication",
            status: .inProgress,
            pr: samplePR
        )
        
        XCTAssertEqual(task.prState, PRState.open)
    }
    
    func testPRStateReturnsMergedForMergedPR() throws {
        // Should return PRState.merged for merged PR
        let mergedPR = makeMergedPR()
        let task = TaskWithPR(
            taskHash: "b4c3d2e1",
            description: "Add input validation",
            status: .completed,
            pr: mergedPR
        )
        
        XCTAssertEqual(task.prState, PRState.merged)
    }
    
    func testPRStateReturnsNoneWhenNoPR() throws {
        // Should return None for prState when PR is None
        let task = TaskWithPR(
            taskHash: "c5d4e3f2",
            description: "Add logging",
            status: .pending,
            pr: nil
        )
        
        XCTAssertNil(task.prState)
    }
    
    func testCompletedTaskWithMergedPR() throws {
        // Should correctly represent completed task with merged PR
        let mergedPR = makeMergedPR()
        let task = TaskWithPR(
            taskHash: "b4c3d2e1",
            description: "Add input validation",
            status: .completed,
            pr: mergedPR
        )
        
        XCTAssertEqual(task.status, .completed)
        XCTAssertTrue(task.hasPR)
        XCTAssertEqual(task.prNumber, 41)
        XCTAssertEqual(task.prState, PRState.merged)
    }
    
    // MARK: - ProjectStats Task Fields Tests
    
    func testProjectStatsInitializesEmptyTasksList() throws {
        // Should initialize with empty tasks list
        let stats = ProjectStats(projectName: "my-project", specPath: "claude-chain/my-project/spec.md")
        
        XCTAssertEqual(stats.tasks, [] as [TaskWithPR])
        XCTAssertTrue(stats.tasks is [TaskWithPR])
    }
    
    func testProjectStatsInitializesEmptyOrphanedPRsList() throws {
        // Should initialize with empty orphanedPRs list
        let stats = ProjectStats(projectName: "my-project", specPath: "claude-chain/my-project/spec.md")
        
        XCTAssertEqual(stats.orphanedPRs, [] as [GitHubPullRequest])
        XCTAssertTrue(stats.orphanedPRs is [GitHubPullRequest])
    }
    
    func testProjectStatsCanAddTasks() throws {
        // Should allow adding TaskWithPR to tasks list
        let stats = ProjectStats(projectName: "my-project", specPath: "claude-chain/my-project/spec.md")
        let samplePR = makeSamplePR()
        
        let task = TaskWithPR(
            taskHash: "a3f2b891",
            description: "Add feature",
            status: .inProgress,
            pr: samplePR
        )
        
        stats.tasks.append(task)
        
        XCTAssertEqual(stats.tasks.count, 1)
        XCTAssertEqual(stats.tasks[0].taskHash, "a3f2b891")
    }
    
    func testProjectStatsCanAddOrphanedPRs() throws {
        // Should allow adding GitHubPullRequest to orphanedPRs list
        let stats = ProjectStats(projectName: "my-project", specPath: "claude-chain/my-project/spec.md")
        let samplePR = makeSamplePR()
        
        stats.orphanedPRs.append(samplePR)
        
        XCTAssertEqual(stats.orphanedPRs.count, 1)
        XCTAssertEqual(stats.orphanedPRs[0].number, 42)
    }
    
    func testProjectStatsTasksAndOrphanedPRsIndependent() throws {
        // Should maintain tasks and orphanedPRs as independent lists
        let stats = ProjectStats(projectName: "my-project", specPath: "claude-chain/my-project/spec.md")
        let samplePR = makeSamplePR()
        
        let task = TaskWithPR(
            taskHash: "a3f2b891",
            description: "Add feature",
            status: .pending,
            pr: nil
        )
        
        stats.tasks.append(task)
        stats.orphanedPRs.append(samplePR)
        
        XCTAssertEqual(stats.tasks.count, 1)
        XCTAssertEqual(stats.orphanedPRs.count, 1)
        XCTAssertNil(stats.tasks[0].pr)
        XCTAssertEqual(stats.orphanedPRs[0].number, 42)
    }
}