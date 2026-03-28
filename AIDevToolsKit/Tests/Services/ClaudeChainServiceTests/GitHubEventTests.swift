/// Unit tests for GitHub event context module.
///
/// Tests GitHubEventContext from ClaudeChainService.GitHubEvent.
/// Tests cover parsing of different event types, skip logic, and project extraction.
import XCTest
import Foundation
@testable import ClaudeChainService

final class TestGitHubEventContextParsing: XCTestCase {
    /// Tests for GitHubEventContext.fromJSON parsing.
    
    func testParseWorkflowDispatchEvent() throws {
        /// Should parse workflow_dispatch event with inputs.
        let eventData: [String: Any] = [
            "inputs": [
                "project_name": "my-refactor"
            ],
            "ref": "refs/heads/main"
        ]
        let eventJSON = try jsonString(from: eventData)
        
        let context = try GitHubEventContext.fromJSON(eventName: "workflow_dispatch", eventJSON: eventJSON)
        
        XCTAssertEqual(context.eventName, "workflow_dispatch")
        XCTAssertEqual(context.inputs, ["project_name": "my-refactor"])
        XCTAssertEqual(context.refName, "main")
    }
    
    func testParseWorkflowDispatchWithEmptyInputs() throws {
        /// Should handle workflow_dispatch with no inputs.
        let eventData: [String: Any] = [
            "inputs": NSNull(),
            "ref": "refs/heads/develop"
        ]
        let eventJSON = try jsonString(from: eventData)
        
        let context = try GitHubEventContext.fromJSON(eventName: "workflow_dispatch", eventJSON: eventJSON)
        
        XCTAssertEqual(context.eventName, "workflow_dispatch")
        XCTAssertEqual(context.inputs, [:])
        XCTAssertEqual(context.refName, "develop")
    }
    
    func testParsePullRequestClosedMerged() throws {
        /// Should parse pull_request:closed event when merged.
        let eventData: [String: Any] = [
            "action": "closed",
            "pull_request": [
                "number": 42,
                "merged": true,
                "base": ["ref": "main"],
                "head": ["ref": "claude-chain-my-project-a3f2b891"],
                "labels": [
                    ["name": "claudechain"],
                    ["name": "enhancement"]
                ]
            ]
        ]
        let eventJSON = try jsonString(from: eventData)
        
        let context = try GitHubEventContext.fromJSON(eventName: "pull_request", eventJSON: eventJSON)
        
        XCTAssertEqual(context.eventName, "pull_request")
        XCTAssertEqual(context.prNumber, 42)
        XCTAssertEqual(context.prMerged, true)
        XCTAssertEqual(context.baseRef, "main")
        XCTAssertEqual(context.headRef, "claude-chain-my-project-a3f2b891")
        XCTAssertTrue(context.prLabels.contains("claudechain"))
        XCTAssertTrue(context.prLabels.contains("enhancement"))
    }
    
    func testParsePullRequestClosedNotMerged() throws {
        /// Should parse pull_request:closed event when not merged.
        let eventData: [String: Any] = [
            "action": "closed",
            "pull_request": [
                "number": 43,
                "merged": false,
                "base": ["ref": "main"],
                "head": ["ref": "feature/some-feature"],
                "labels": []
            ]
        ]
        let eventJSON = try jsonString(from: eventData)
        
        let context = try GitHubEventContext.fromJSON(eventName: "pull_request", eventJSON: eventJSON)
        
        XCTAssertEqual(context.prNumber, 43)
        XCTAssertEqual(context.prMerged, false)
        XCTAssertEqual(context.prLabels, [])
    }
    
    func testParsePushEvent() throws {
        /// Should parse push event with before/after SHAs.
        let eventData: [String: Any] = [
            "ref": "refs/heads/feature-branch",
            "before": "abc123456",
            "after": "def789012"
        ]
        let eventJSON = try jsonString(from: eventData)
        
        let context = try GitHubEventContext.fromJSON(eventName: "push", eventJSON: eventJSON)
        
        XCTAssertEqual(context.eventName, "push")
        XCTAssertEqual(context.refName, "feature-branch")
        XCTAssertEqual(context.beforeSHA, "abc123456")
        XCTAssertEqual(context.afterSHA, "def789012")
    }
    
    func testParsePushToMainBranch() throws {
        /// Should parse push to main branch.
        let eventData: [String: Any] = [
            "ref": "refs/heads/main",
            "before": "123abc456",
            "after": "456def789"
        ]
        let eventJSON = try jsonString(from: eventData)
        
        let context = try GitHubEventContext.fromJSON(eventName: "push", eventJSON: eventJSON)
        
        XCTAssertEqual(context.refName, "main")
        XCTAssertEqual(context.beforeSHA, "123abc456")
        XCTAssertEqual(context.afterSHA, "456def789")
    }
    
    func testParseUnknownEvent() throws {
        /// Should handle unknown event types without error.
        let eventJSON = try jsonString(from: [:])
        
        let context = try GitHubEventContext.fromJSON(eventName: "unknown_event", eventJSON: eventJSON)
        
        XCTAssertEqual(context.eventName, "unknown_event")
        XCTAssertNil(context.prNumber)
        XCTAssertNil(context.refName)
        XCTAssertEqual(context.inputs, [:])
    }
    
    func testParseWithMalformedJSON() {
        /// Should raise error for invalid JSON.
        let malformedJSON = "{'invalid': json}"
        
        XCTAssertThrowsError(try GitHubEventContext.fromJSON(eventName: "push", eventJSON: malformedJSON))
    }
    
    private func jsonString(from dict: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dict, options: [])
        return String(data: data, encoding: .utf8) ?? ""
    }
}

final class TestShouldSkipLogic: XCTestCase {
    /// Tests for shouldSkip method.
    
    func testShouldSkipMergedPRWithRequiredLabel() {
        /// Should NOT skip merged PR with required label.
        let context = GitHubEventContext(
            eventName: "pull_request",
            prMerged: true,
            prLabels: ["claudechain", "feature"]
        )
        
        let (shouldSkip, reason) = context.shouldSkip(requiredLabel: "claudechain")
        
        XCTAssertFalse(shouldSkip)
        XCTAssertEqual(reason, "")
    }
    
    func testShouldSkipUnmergedPR() {
        /// Should skip unmerged (closed but not merged) PR.
        let context = GitHubEventContext(
            eventName: "pull_request",
            prMerged: false,
            prLabels: ["claudechain"]
        )
        
        let (shouldSkip, reason) = context.shouldSkip()
        
        XCTAssertTrue(shouldSkip)
        XCTAssertEqual(reason, "PR was closed but not merged")
    }
    
    func testShouldSkipPRWithoutRequiredLabel() {
        /// Should skip merged PR without required label.
        let context = GitHubEventContext(
            eventName: "pull_request",
            prMerged: true,
            prLabels: ["feature", "enhancement"]
        )
        
        let (shouldSkip, reason) = context.shouldSkip(requiredLabel: "claudechain")
        
        XCTAssertTrue(shouldSkip)
        XCTAssertEqual(reason, "PR does not have required label 'claudechain'")
    }
    
    func testShouldNotSkipPRWhenLabelCheckDisabled() {
        /// Should NOT skip PR when label checking is disabled.
        let context = GitHubEventContext(
            eventName: "pull_request",
            prMerged: true,
            prLabels: ["feature"]  // No claudechain label
        )
        
        let (shouldSkip, reason) = context.shouldSkip(
            requiredLabel: "claudechain",
            requireLabelForPR: false
        )
        
        XCTAssertFalse(shouldSkip)
        XCTAssertEqual(reason, "")
    }
    
    func testShouldNotSkipPushEvent() {
        /// Should NOT skip push events.
        let context = GitHubEventContext(
            eventName: "push",
            refName: "main"
        )
        
        let (shouldSkip, reason) = context.shouldSkip()
        
        XCTAssertFalse(shouldSkip)
        XCTAssertEqual(reason, "")
    }
    
    func testShouldNotSkipWorkflowDispatch() {
        /// Should NOT skip workflow_dispatch events.
        let context = GitHubEventContext(
            eventName: "workflow_dispatch",
            inputs: ["project_name": "my-project"]
        )
        
        let (shouldSkip, reason) = context.shouldSkip()
        
        XCTAssertFalse(shouldSkip)
        XCTAssertEqual(reason, "")
    }
    
    func testShouldSkipWithCustomLabel() {
        /// Should respect custom required label.
        let context = GitHubEventContext(
            eventName: "pull_request",
            prMerged: true,
            prLabels: ["claudechain", "custom-label"]
        )
        
        // Should skip when looking for different label
        let (shouldSkip1, reason1) = context.shouldSkip(requiredLabel: "different-label")
        XCTAssertTrue(shouldSkip1)
        XCTAssertTrue(reason1.contains("different-label"))
        
        // Should NOT skip when PR has the custom label
        let (shouldSkip2, reason2) = context.shouldSkip(requiredLabel: "custom-label")
        XCTAssertFalse(shouldSkip2)
        XCTAssertEqual(reason2, "")
    }
    
    func testShouldNotSkipWithEmptyRequiredLabel() {
        /// Should NOT skip when required label is empty (disables label check).
        let context = GitHubEventContext(
            eventName: "pull_request",
            prMerged: true,
            prLabels: []  // No labels
        )
        
        let (shouldSkip, reason) = context.shouldSkip(requiredLabel: "")
        
        XCTAssertFalse(shouldSkip)
        XCTAssertEqual(reason, "")
    }
}

final class TestGetCheckoutRef: XCTestCase {
    /// Tests for getCheckoutRef method.
    
    func testGetCheckoutRefForPush() throws {
        /// Should return ref_name for push events.
        let context = GitHubEventContext(
            eventName: "push",
            refName: "feature-branch"
        )
        
        let checkoutRef = try context.getCheckoutRef()
        
        XCTAssertEqual(checkoutRef, "feature-branch")
    }
    
    func testGetCheckoutRefForPullRequest() throws {
        /// Should return base_ref for pull_request events.
        let context = GitHubEventContext(
            eventName: "pull_request",
            baseRef: "main"
        )
        
        let checkoutRef = try context.getCheckoutRef()
        
        XCTAssertEqual(checkoutRef, "main")
    }
    
    func testGetCheckoutRefForWorkflowDispatch() throws {
        /// Should return ref_name for workflow_dispatch events.
        let context = GitHubEventContext(
            eventName: "workflow_dispatch",
            refName: "develop"
        )
        
        let checkoutRef = try context.getCheckoutRef()
        
        XCTAssertEqual(checkoutRef, "develop")
    }
    
    func testGetCheckoutRefRaisesErrorForMissingPushRef() {
        /// Should raise error when push event is missing ref_name.
        let context = GitHubEventContext(
            eventName: "push",
            refName: nil
        )
        
        XCTAssertThrowsError(try context.getCheckoutRef()) { error in
            XCTAssertTrue(error is ConfigurationError)
            if let configError = error as? ConfigurationError {
                XCTAssertTrue(configError.message.contains("Push event missing ref_name"))
            }
        }
    }
    
    func testGetCheckoutRefRaisesErrorForMissingPRBaseRef() {
        /// Should raise error when pull_request event is missing base_ref.
        let context = GitHubEventContext(
            eventName: "pull_request",
            baseRef: nil
        )
        
        XCTAssertThrowsError(try context.getCheckoutRef()) { error in
            XCTAssertTrue(error is ConfigurationError)
            if let configError = error as? ConfigurationError {
                XCTAssertTrue(configError.message.contains("Pull request event missing base_ref"))
            }
        }
    }
    
    func testGetCheckoutRefRaisesErrorForUnknownEvent() {
        /// Should raise error for unknown event types.
        let context = GitHubEventContext(eventName: "unknown_event")
        
        XCTAssertThrowsError(try context.getCheckoutRef()) { error in
            XCTAssertTrue(error is ConfigurationError)
            if let configError = error as? ConfigurationError {
                XCTAssertTrue(configError.message.contains("Unknown event type"))
            }
        }
    }
}

final class TestGetChangedFilesContext: XCTestCase {
    /// Tests for getChangedFilesContext method.
    
    func testGetChangedFilesContextForPush() {
        /// Should return before/after SHAs for push events.
        let context = GitHubEventContext(
            eventName: "push",
            beforeSHA: "abc123",
            afterSHA: "def456"
        )
        
        let changedContext = context.getChangedFilesContext()
        
        XCTAssertNotNil(changedContext)
        XCTAssertEqual(changedContext?.baseRef, "abc123")
        XCTAssertEqual(changedContext?.headRef, "def456")
    }
    
    func testGetChangedFilesContextForPullRequest() {
        /// Should return base/head refs for pull_request events.
        let context = GitHubEventContext(
            eventName: "pull_request",
            baseRef: "main",
            headRef: "feature-branch"
        )
        
        let changedContext = context.getChangedFilesContext()
        
        XCTAssertNotNil(changedContext)
        XCTAssertEqual(changedContext?.baseRef, "main")
        XCTAssertEqual(changedContext?.headRef, "feature-branch")
    }
    
    func testGetChangedFilesContextForWorkflowDispatch() {
        /// Should return nil for workflow_dispatch events.
        let context = GitHubEventContext(
            eventName: "workflow_dispatch",
            inputs: ["project_name": "test"]
        )
        
        let changedContext = context.getChangedFilesContext()
        
        XCTAssertNil(changedContext)
    }
    
    func testGetChangedFilesContextWithMissingData() {
        /// Should return nil when required data is missing.
        let pushContext = GitHubEventContext(
            eventName: "push",
            beforeSHA: "abc123",
            afterSHA: nil  // Missing after SHA
        )
        
        let prContext = GitHubEventContext(
            eventName: "pull_request",
            baseRef: "main",
            headRef: nil  // Missing head ref
        )
        
        XCTAssertNil(pushContext.getChangedFilesContext())
        XCTAssertNil(prContext.getChangedFilesContext())
    }
}

final class TestHasLabel: XCTestCase {
    /// Tests for hasLabel method.
    
    func testHasLabelReturnsTrueWhenLabelExists() {
        /// Should return true when PR has the label.
        let context = GitHubEventContext(
            eventName: "pull_request",
            prLabels: ["claudechain", "feature", "bug"]
        )
        
        XCTAssertTrue(context.hasLabel("claudechain"))
        XCTAssertTrue(context.hasLabel("feature"))
        XCTAssertTrue(context.hasLabel("bug"))
    }
    
    func testHasLabelReturnsFalseWhenLabelMissing() {
        /// Should return false when PR doesn't have the label.
        let context = GitHubEventContext(
            eventName: "pull_request",
            prLabels: ["feature", "enhancement"]
        )
        
        XCTAssertFalse(context.hasLabel("claudechain"))
        XCTAssertFalse(context.hasLabel("bug"))
        XCTAssertFalse(context.hasLabel("nonexistent"))
    }
    
    func testHasLabelWithNoLabels() {
        /// Should return false when PR has no labels.
        let context = GitHubEventContext(
            eventName: "pull_request",
            prLabels: []
        )
        
        XCTAssertFalse(context.hasLabel("any-label"))
    }
    
    func testHasLabelCaseSensitive() {
        /// Should be case-sensitive when checking labels.
        let context = GitHubEventContext(
            eventName: "pull_request",
            prLabels: ["ClaudeChain"]
        )
        
        XCTAssertTrue(context.hasLabel("ClaudeChain"))
        XCTAssertFalse(context.hasLabel("claudechain"))
        XCTAssertFalse(context.hasLabel("CLAUDECHAIN"))
    }
}