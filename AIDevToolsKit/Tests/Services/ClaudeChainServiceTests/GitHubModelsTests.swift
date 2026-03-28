/// Unit tests for GitHub domain models
///
/// Tests GitHubUser, GitHubPullRequest, and GitHubPullRequestList models
/// from ClaudeChainService.GitHubModels
import XCTest
import Foundation
@testable import ClaudeChainService

final class TestGitHubUser: XCTestCase {
    /// Tests for GitHubUser model
    
    func testUserCreationWithAllFields() {
        /// Should create user with all fields
        let user = GitHubUser(
            login: "octocat",
            name: "The Octocat",
            avatarURL: "https://github.com/images/octocat.png"
        )
        
        XCTAssertEqual(user.login, "octocat")
        XCTAssertEqual(user.name, "The Octocat")
        XCTAssertEqual(user.avatarURL, "https://github.com/images/octocat.png")
    }
    
    func testUserCreationWithMinimalFields() {
        /// Should create user with only login (required field)
        let user = GitHubUser(login: "testuser")
        
        XCTAssertEqual(user.login, "testuser")
        XCTAssertNil(user.name)
        XCTAssertNil(user.avatarURL)
    }
    
    func testUserFromDictWithAllFields() {
        /// Should parse user from GitHub API response with all fields
        let data: [String: Any] = [
            "login": "reviewer1",
            "name": "Reviewer One",
            "avatar_url": "https://avatars.githubusercontent.com/u/123"
        ]
        
        let user = GitHubUser.fromDict(data)
        
        XCTAssertEqual(user.login, "reviewer1")
        XCTAssertEqual(user.name, "Reviewer One")
        XCTAssertEqual(user.avatarURL, "https://avatars.githubusercontent.com/u/123")
    }
    
    func testUserFromDictWithMinimalFields() {
        /// Should parse user with only login field
        let data: [String: Any] = ["login": "minimal_user"]
        
        let user = GitHubUser.fromDict(data)
        
        XCTAssertEqual(user.login, "minimal_user")
        XCTAssertNil(user.name)
        XCTAssertNil(user.avatarURL)
    }
    
    func testUserFromDictWithMissingLogin() {
        /// Should handle missing login field gracefully
        let data: [String: Any] = [
            "name": "No Login User",
            "avatar_url": "https://example.com/avatar.png"
        ]
        
        let user = GitHubUser.fromDict(data)
        
        XCTAssertEqual(user.login, "")
        XCTAssertEqual(user.name, "No Login User")
        XCTAssertEqual(user.avatarURL, "https://example.com/avatar.png")
    }
}

final class TestPRState: XCTestCase {
    /// Tests for PRState enum
    
    func testPRStateFromValidStrings() throws {
        /// Should parse valid state strings case-insensitively
        let testCases = [
            ("open", PRState.open),
            ("OPEN", PRState.open),
            ("Open", PRState.open),
            ("closed", PRState.closed),
            ("CLOSED", PRState.closed),
            ("Closed", PRState.closed),
            ("merged", PRState.merged),
            ("MERGED", PRState.merged),
            ("Merged", PRState.merged)
        ]
        
        for (input, expected) in testCases {
            let result = try PRState.fromString(input)
            XCTAssertEqual(result, expected, "Failed for input: \(input)")
        }
    }
    
    func testPRStateFromInvalidString() {
        /// Should throw ConfigurationError for invalid state
        XCTAssertThrowsError(try PRState.fromString("invalid")) { error in
            XCTAssertTrue(error is ConfigurationError)
            if let configError = error as? ConfigurationError {
                XCTAssertTrue(configError.message.contains("Invalid PR state"))
            }
        }
    }
}

final class TestGitHubPullRequest: XCTestCase {
    /// Tests for GitHubPullRequest model
    
    func testPRCreationWithAllFields() {
        /// Should create PR with all fields
        let createdAt = Date()
        let mergedAt = Date().addingTimeInterval(3600)
        let assignees = [GitHubUser(login: "reviewer1")]
        
        let pr = GitHubPullRequest(
            number: 123,
            title: "Feature: Add tests",
            state: "merged",
            createdAt: createdAt,
            mergedAt: mergedAt,
            assignees: assignees,
            labels: ["feature", "tests"],
            headRefName: "feature-branch",
            baseRefName: "main",
            url: "https://github.com/owner/repo/pull/123"
        )
        
        XCTAssertEqual(pr.number, 123)
        XCTAssertEqual(pr.title, "Feature: Add tests")
        XCTAssertEqual(pr.state, "merged")
        XCTAssertEqual(pr.createdAt, createdAt)
        XCTAssertEqual(pr.mergedAt, mergedAt)
        XCTAssertEqual(pr.assignees.count, 1)
        XCTAssertEqual(pr.labels, ["feature", "tests"])
        XCTAssertEqual(pr.headRefName, "feature-branch")
        XCTAssertEqual(pr.baseRefName, "main")
        XCTAssertEqual(pr.url, "https://github.com/owner/repo/pull/123")
    }
    
    func testPRFromDictWithAllFields() {
        /// Should parse PR from GitHub API response with all fields
        let data: [String: Any] = [
            "number": 456,
            "title": "Fix: Bug in parser",
            "state": "open",
            "createdAt": "2024-01-15T10:30:00Z",
            "mergedAt": NSNull(),
            "assignees": [
                ["login": "reviewer1", "name": "Reviewer One"],
                ["login": "reviewer2"]
            ],
            "labels": [
                ["name": "bug"],
                ["name": "priority-high"]
            ],
            "headRefName": "fix-parser-bug",
            "baseRefName": "main",
            "url": "https://github.com/owner/repo/pull/456"
        ]
        
        let pr = GitHubPullRequest.fromDict(data)
        
        XCTAssertEqual(pr.number, 456)
        XCTAssertEqual(pr.title, "Fix: Bug in parser")
        XCTAssertEqual(pr.state, "open")
        XCTAssertEqual(pr.assignees.count, 2)
        XCTAssertEqual(pr.assignees[0].login, "reviewer1")
        XCTAssertEqual(pr.assignees[1].login, "reviewer2")
        XCTAssertEqual(pr.labels, ["bug", "priority-high"])
        XCTAssertEqual(pr.headRefName, "fix-parser-bug")
        XCTAssertEqual(pr.baseRefName, "main")
        XCTAssertEqual(pr.url, "https://github.com/owner/repo/pull/456")
        XCTAssertNil(pr.mergedAt)
    }
    
    func testPRFromDictWithMinimalFields() {
        /// Should parse PR with minimal required fields
        let data: [String: Any] = [
            "number": 789,
            "title": "Minimal PR",
            "state": "open",
            "createdAt": "2024-01-15T11:00:00Z"
        ]
        
        let pr = GitHubPullRequest.fromDict(data)
        
        XCTAssertEqual(pr.number, 789)
        XCTAssertEqual(pr.title, "Minimal PR")
        XCTAssertEqual(pr.state, "open")
        XCTAssertTrue(pr.assignees.isEmpty)
        XCTAssertTrue(pr.labels.isEmpty)
        XCTAssertNil(pr.headRefName)
        XCTAssertNil(pr.baseRefName)
        XCTAssertNil(pr.url)
        XCTAssertNil(pr.mergedAt)
    }
    
    func testPRFromDictWithMergedState() {
        /// Should parse merged PR with mergedAt timestamp
        let data: [String: Any] = [
            "number": 100,
            "title": "Merged Feature",
            "state": "closed",
            "createdAt": "2024-01-15T09:00:00Z",
            "mergedAt": "2024-01-15T15:30:00Z",
            "assignees": [],
            "labels": []
        ]
        
        let pr = GitHubPullRequest.fromDict(data)
        
        XCTAssertEqual(pr.state, "closed")
        XCTAssertNotNil(pr.mergedAt)
        XCTAssertTrue(pr.isMerged())
    }
    
    func testPRStateCheckers() {
        /// Should correctly identify PR states
        let openPR = GitHubPullRequest(
            number: 1,
            title: "Open PR",
            state: "open",
            createdAt: Date()
        )
        
        let closedPR = GitHubPullRequest(
            number: 2,
            title: "Closed PR",
            state: "closed",
            createdAt: Date()
        )
        
        let mergedPR = GitHubPullRequest(
            number: 3,
            title: "Merged PR",
            state: "merged",
            createdAt: Date(),
            mergedAt: Date()
        )
        
        XCTAssertTrue(openPR.isOpen())
        XCTAssertFalse(openPR.isClosed())
        XCTAssertFalse(openPR.isMerged())
        
        XCTAssertFalse(closedPR.isOpen())
        XCTAssertTrue(closedPR.isClosed())
        XCTAssertFalse(closedPR.isMerged())
        
        XCTAssertFalse(mergedPR.isOpen())
        XCTAssertFalse(mergedPR.isClosed())
        XCTAssertTrue(mergedPR.isMerged())
    }
    
    func testHasLabel() {
        /// Should correctly check for labels
        let pr = GitHubPullRequest(
            number: 1,
            title: "Test PR",
            state: "open",
            createdAt: Date(),
            labels: ["bug", "priority-high", "needs-review"]
        )
        
        XCTAssertTrue(pr.hasLabel("bug"))
        XCTAssertTrue(pr.hasLabel("priority-high"))
        XCTAssertFalse(pr.hasLabel("feature"))
        XCTAssertFalse(pr.hasLabel("enhancement"))
    }
    
    func testGetAssigneeLogins() {
        /// Should return list of assignee logins
        let assignees = [
            GitHubUser(login: "alice"),
            GitHubUser(login: "bob"),
            GitHubUser(login: "charlie")
        ]
        
        let pr = GitHubPullRequest(
            number: 1,
            title: "Test PR",
            state: "open",
            createdAt: Date(),
            assignees: assignees
        )
        
        let logins = pr.getAssigneeLogins()
        
        XCTAssertEqual(logins, ["alice", "bob", "charlie"])
    }
    
    func testProjectNameExtraction() {
        /// Should extract project name from branch name
        let validPR = GitHubPullRequest(
            number: 1,
            title: "Test PR",
            state: "open",
            createdAt: Date(),
            headRefName: "claude-chain-my-project-12abcdef"
        )
        
        let invalidPR = GitHubPullRequest(
            number: 2,
            title: "Regular PR",
            state: "open",
            createdAt: Date(),
            headRefName: "feature/regular-branch"
        )
        
        let noBranchPR = GitHubPullRequest(
            number: 3,
            title: "No Branch PR",
            state: "open",
            createdAt: Date()
        )
        
        XCTAssertEqual(validPR.projectName, "my-project")
        XCTAssertNil(invalidPR.projectName)
        XCTAssertNil(noBranchPR.projectName)
    }
    
    func testTaskHashExtraction() {
        /// Should extract task hash from branch name
        let pr = GitHubPullRequest(
            number: 1,
            title: "Test PR",
            state: "open",
            createdAt: Date(),
            headRefName: "claude-chain-my-project-12abcdef"
        )
        
        XCTAssertEqual(pr.taskHash, "12abcdef")
    }
    
    func testTaskDescriptionWithPrefix() {
        /// Should strip ClaudeChain prefix from task description
        let prefixedPR = GitHubPullRequest(
            number: 1,
            title: "ClaudeChain: Implement new feature",
            state: "open",
            createdAt: Date()
        )
        
        let regularPR = GitHubPullRequest(
            number: 2,
            title: "Regular PR title",
            state: "open",
            createdAt: Date()
        )
        
        XCTAssertEqual(prefixedPR.taskDescription, "Implement new feature")
        XCTAssertEqual(regularPR.taskDescription, "Regular PR title")
    }
    
    func testIsClaudeChainPR() {
        /// Should correctly identify ClaudeChain PRs
        let claudeChainPR = GitHubPullRequest(
            number: 1,
            title: "Test PR",
            state: "open",
            createdAt: Date(),
            headRefName: "claude-chain-my-project-12abcdef"
        )
        
        let regularPR = GitHubPullRequest(
            number: 2,
            title: "Regular PR",
            state: "open",
            createdAt: Date(),
            headRefName: "feature/regular-branch"
        )
        
        XCTAssertTrue(claudeChainPR.isClaudeChainPR)
        XCTAssertFalse(regularPR.isClaudeChainPR)
    }
    
    func testDaysOpen() {
        /// Should calculate days PR has been open
        let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        
        let openPR = GitHubPullRequest(
            number: 1,
            title: "Open PR",
            state: "open",
            createdAt: twoDaysAgo
        )
        
        let mergedPR = GitHubPullRequest(
            number: 2,
            title: "Merged PR",
            state: "merged",
            createdAt: twoDaysAgo,
            mergedAt: Date().addingTimeInterval(-24 * 60 * 60) // Merged 1 day ago
        )
        
        XCTAssertEqual(openPR.daysOpen, 2)
        XCTAssertEqual(mergedPR.daysOpen, 1)
    }
    
    func testIsStale() {
        /// Should correctly identify stale PRs
        let oldDate = Date().addingTimeInterval(-10 * 24 * 60 * 60) // 10 days ago
        let recentDate = Date().addingTimeInterval(-2 * 24 * 60 * 60) // 2 days ago
        
        let oldPR = GitHubPullRequest(
            number: 1,
            title: "Old PR",
            state: "open",
            createdAt: oldDate
        )
        
        let recentPR = GitHubPullRequest(
            number: 2,
            title: "Recent PR",
            state: "open",
            createdAt: recentDate
        )
        
        XCTAssertTrue(oldPR.isStale(stalePRDays: 7))
        XCTAssertFalse(recentPR.isStale(stalePRDays: 7))
    }
    
    func testFirstAssignee() {
        /// Should return first assignee login
        let assignees = [
            GitHubUser(login: "alice"),
            GitHubUser(login: "bob")
        ]
        
        let prWithAssignees = GitHubPullRequest(
            number: 1,
            title: "Test PR",
            state: "open",
            createdAt: Date(),
            assignees: assignees
        )
        
        let prWithoutAssignees = GitHubPullRequest(
            number: 2,
            title: "Test PR",
            state: "open",
            createdAt: Date()
        )
        
        XCTAssertEqual(prWithAssignees.firstAssignee, "alice")
        XCTAssertNil(prWithoutAssignees.firstAssignee)
    }
}

final class TestGitHubPullRequestList: XCTestCase {
    /// Tests for GitHubPullRequestList
    
    private func createSamplePRs() -> [GitHubPullRequest] {
        return [
            GitHubPullRequest(
                number: 1,
                title: "Open Bug Fix",
                state: "open",
                createdAt: Date(),
                assignees: [GitHubUser(login: "alice")],
                labels: ["bug", "priority-high"]
            ),
            GitHubPullRequest(
                number: 2,
                title: "Merged Feature",
                state: "merged",
                createdAt: Date().addingTimeInterval(-3600),
                mergedAt: Date(),
                assignees: [GitHubUser(login: "bob")],
                labels: ["feature"]
            ),
            GitHubPullRequest(
                number: 3,
                title: "Closed PR",
                state: "closed",
                createdAt: Date().addingTimeInterval(-7200),
                assignees: [GitHubUser(login: "alice"), GitHubUser(login: "charlie")],
                labels: ["wontfix"]
            )
        ]
    }
    
    func testPRListCreation() {
        /// Should create PR list with given PRs
        let prs = createSamplePRs()
        let prList = GitHubPullRequestList(pullRequests: prs)
        
        XCTAssertEqual(prList.pullRequests.count, 3)
        XCTAssertEqual(prList.count(), 3)
    }
    
    func testFromJSONArray() {
        /// Should parse PR list from JSON array
        let jsonData: [[String: Any]] = [
            [
                "number": 123,
                "title": "Test PR 1",
                "state": "open",
                "createdAt": "2024-01-15T10:00:00Z",
                "assignees": [],
                "labels": []
            ],
            [
                "number": 124,
                "title": "Test PR 2",
                "state": "merged",
                "createdAt": "2024-01-15T11:00:00Z",
                "mergedAt": "2024-01-15T12:00:00Z",
                "assignees": [],
                "labels": []
            ]
        ]
        
        let prList = GitHubPullRequestList.fromJSONArray(jsonData)
        
        XCTAssertEqual(prList.count(), 2)
        XCTAssertEqual(prList.pullRequests[0].number, 123)
        XCTAssertEqual(prList.pullRequests[1].number, 124)
    }
    
    func testFilterByState() {
        /// Should filter PRs by state
        let prList = GitHubPullRequestList(pullRequests: createSamplePRs())
        
        let openPRs = prList.filterByState("open")
        let mergedPRs = prList.filterByState("merged")
        let closedPRs = prList.filterByState("closed")
        
        XCTAssertEqual(openPRs.count(), 1)
        XCTAssertEqual(openPRs.pullRequests[0].number, 1)
        
        XCTAssertEqual(mergedPRs.count(), 1)
        XCTAssertEqual(mergedPRs.pullRequests[0].number, 2)
        
        XCTAssertEqual(closedPRs.count(), 1)
        XCTAssertEqual(closedPRs.pullRequests[0].number, 3)
    }
    
    func testFilterByLabel() {
        /// Should filter PRs by label
        let prList = GitHubPullRequestList(pullRequests: createSamplePRs())
        
        let bugPRs = prList.filterByLabel("bug")
        let featurePRs = prList.filterByLabel("feature")
        let nonExistentPRs = prList.filterByLabel("nonexistent")
        
        XCTAssertEqual(bugPRs.count(), 1)
        XCTAssertEqual(bugPRs.pullRequests[0].number, 1)
        
        XCTAssertEqual(featurePRs.count(), 1)
        XCTAssertEqual(featurePRs.pullRequests[0].number, 2)
        
        XCTAssertEqual(nonExistentPRs.count(), 0)
    }
    
    func testFilterMerged() {
        /// Should filter to only merged PRs
        let prList = GitHubPullRequestList(pullRequests: createSamplePRs())
        
        let mergedPRs = prList.filterMerged()
        
        XCTAssertEqual(mergedPRs.count(), 1)
        XCTAssertEqual(mergedPRs.pullRequests[0].number, 2)
        XCTAssertTrue(mergedPRs.pullRequests[0].isMerged())
    }
    
    func testFilterOpen() {
        /// Should filter to only open PRs
        let prList = GitHubPullRequestList(pullRequests: createSamplePRs())
        
        let openPRs = prList.filterOpen()
        
        XCTAssertEqual(openPRs.count(), 1)
        XCTAssertEqual(openPRs.pullRequests[0].number, 1)
        XCTAssertTrue(openPRs.pullRequests[0].isOpen())
    }
    
    func testFilterByDate() {
        /// Should filter PRs by creation date
        let prList = GitHubPullRequestList(pullRequests: createSamplePRs())
        let cutoffDate = Date().addingTimeInterval(-1800) // 30 minutes ago
        
        let recentPRs = prList.filterByDate(since: cutoffDate, dateField: "created_at")
        
        XCTAssertEqual(recentPRs.count(), 1)
        XCTAssertEqual(recentPRs.pullRequests[0].number, 1) // Most recent PR
    }
    
    func testGroupByAssignee() {
        /// Should group PRs by assignee
        let prList = GitHubPullRequestList(pullRequests: createSamplePRs())
        
        let grouped = prList.groupByAssignee()
        
        XCTAssertEqual(grouped.keys.count, 3)
        XCTAssertEqual(grouped["alice"]?.count, 2) // PRs 1 and 3
        XCTAssertEqual(grouped["bob"]?.count, 1)   // PR 2
        XCTAssertEqual(grouped["charlie"]?.count, 1) // PR 3
        
        // Verify alice has both PRs 1 and 3
        let alicePRs = grouped["alice"] ?? []
        let alicePRNumbers = Set(alicePRs.map { $0.number })
        XCTAssertEqual(alicePRNumbers, Set([1, 3]))
    }
}

final class TestWorkflowRun: XCTestCase {
    /// Tests for WorkflowRun model
    
    func testWorkflowRunCreation() {
        /// Should create workflow run with all fields
        let createdAt = Date()
        let run = WorkflowRun(
            databaseID: 123456,
            status: "completed",
            conclusion: "success",
            createdAt: createdAt,
            headBranch: "main",
            url: "https://github.com/owner/repo/actions/runs/123456"
        )
        
        XCTAssertEqual(run.databaseID, 123456)
        XCTAssertEqual(run.status, "completed")
        XCTAssertEqual(run.conclusion, "success")
        XCTAssertEqual(run.createdAt, createdAt)
        XCTAssertEqual(run.headBranch, "main")
        XCTAssertEqual(run.url, "https://github.com/owner/repo/actions/runs/123456")
    }
    
    func testWorkflowRunFromDict() {
        /// Should parse workflow run from GitHub API response
        let data: [String: Any] = [
            "databaseId": 789012,
            "status": "in_progress",
            "conclusion": NSNull(),
            "createdAt": "2024-01-15T10:00:00Z",
            "headBranch": "feature-branch",
            "url": "https://github.com/owner/repo/actions/runs/789012"
        ]
        
        let run = WorkflowRun.fromDict(data)
        
        XCTAssertEqual(run.databaseID, 789012)
        XCTAssertEqual(run.status, "in_progress")
        XCTAssertNil(run.conclusion)
        XCTAssertEqual(run.headBranch, "feature-branch")
        XCTAssertEqual(run.url, "https://github.com/owner/repo/actions/runs/789012")
    }
    
    func testWorkflowRunStatusCheckers() {
        /// Should correctly identify workflow run status
        let completedSuccessRun = WorkflowRun(
            databaseID: 1,
            status: "completed",
            conclusion: "success",
            createdAt: Date(),
            headBranch: "main",
            url: "https://example.com"
        )
        
        let completedFailureRun = WorkflowRun(
            databaseID: 2,
            status: "completed",
            conclusion: "failure",
            createdAt: Date(),
            headBranch: "main",
            url: "https://example.com"
        )
        
        let inProgressRun = WorkflowRun(
            databaseID: 3,
            status: "in_progress",
            conclusion: nil,
            createdAt: Date(),
            headBranch: "main",
            url: "https://example.com"
        )
        
        XCTAssertTrue(completedSuccessRun.isCompleted())
        XCTAssertTrue(completedSuccessRun.isSuccess())
        XCTAssertFalse(completedSuccessRun.isFailure())
        
        XCTAssertTrue(completedFailureRun.isCompleted())
        XCTAssertFalse(completedFailureRun.isSuccess())
        XCTAssertTrue(completedFailureRun.isFailure())
        
        XCTAssertFalse(inProgressRun.isCompleted())
        XCTAssertFalse(inProgressRun.isSuccess())
        XCTAssertFalse(inProgressRun.isFailure())
    }
}

final class TestPRComment: XCTestCase {
    /// Tests for PRComment model
    
    func testPRCommentCreation() {
        /// Should create PR comment with all fields
        let createdAt = Date()
        let comment = PRComment(
            body: "This looks good to me!",
            author: "reviewer1",
            createdAt: createdAt
        )
        
        XCTAssertEqual(comment.body, "This looks good to me!")
        XCTAssertEqual(comment.author, "reviewer1")
        XCTAssertEqual(comment.createdAt, createdAt)
    }
    
    func testPRCommentFromDict() {
        /// Should parse PR comment from GitHub API response
        let data: [String: Any] = [
            "body": "Please fix the typo in line 42.",
            "author": ["login": "alice"],
            "createdAt": "2024-01-15T14:30:00Z"
        ]
        
        let comment = PRComment.fromDict(data)
        
        XCTAssertEqual(comment.body, "Please fix the typo in line 42.")
        XCTAssertEqual(comment.author, "alice")
    }
    
    func testPRCommentFromDictWithStringAuthor() {
        /// Should handle author as string instead of object
        let data: [String: Any] = [
            "body": "Looks good!",
            "author": "bob",
            "createdAt": "2024-01-15T15:00:00Z"
        ]
        
        let comment = PRComment.fromDict(data)
        
        XCTAssertEqual(comment.body, "Looks good!")
        XCTAssertEqual(comment.author, "bob")
    }
    
    func testPRCommentFromDictWithMissingFields() {
        /// Should handle missing fields gracefully
        let data: [String: Any] = [
            "body": "Comment without author",
            "createdAt": "2024-01-15T16:00:00Z"
        ]
        
        let comment = PRComment.fromDict(data)
        
        XCTAssertEqual(comment.body, "Comment without author")
        XCTAssertEqual(comment.author, "")
    }
}