/// Tests for PullRequestCreatedReport domain model
import XCTest
import Foundation
@testable import ClaudeChainService

class PRCreatedReportTests: XCTestCase {
    
    // MARK: - Helper Methods
    
    /// Create a mock CostBreakdown for testing
    private func makeMockCostBreakdown() -> CostBreakdown {
        return CostBreakdown(
            mainCost: 0.15,
            summaryCost: 0.05,
            inputTokens: 1000,
            outputTokens: 500,
            cacheReadTokens: 200,
            cacheWriteTokens: 100
        )
    }
    
    /// Create a mock CostBreakdown with model data
    private func makeMockCostBreakdownWithModels() -> CostBreakdown {
        let model = ModelUsage(
            model: "claude-sonnet-4-20250514",
            cost: 0.20,
            inputTokens: 1000,
            outputTokens: 500,
            cacheReadTokens: 200,
            cacheWriteTokens: 100
        )
        
        return CostBreakdown(
            mainCost: 0.15,
            summaryCost: 0.05,
            inputTokens: 1000,
            outputTokens: 500,
            cacheReadTokens: 200,
            cacheWriteTokens: 100,
            mainModels: [model],
            summaryModels: []
        )
    }
    
    /// Create a basic PullRequestCreatedReport
    private func makeReport() -> PullRequestCreatedReport {
        return PullRequestCreatedReport(
            prNumber: "123",
            prURL: "https://github.com/owner/repo/pull/123",
            projectName: "my-project",
            task: "Fix the login bug",
            costBreakdown: makeMockCostBreakdown(),
            repo: "owner/repo",
            runID: "456789"
        )
    }
    
    /// Create a report with AI summary content
    private func makeReportWithSummary() -> PullRequestCreatedReport {
        return PullRequestCreatedReport(
            prNumber: "123",
            prURL: "https://github.com/owner/repo/pull/123",
            projectName: "my-project",
            task: "Fix the login bug",
            costBreakdown: makeMockCostBreakdown(),
            repo: "owner/repo",
            runID: "456789",
            summaryContent: "This PR fixes a bug in the login flow by adding proper validation."
        )
    }
    
    // MARK: - PullRequestCreatedReport Tests
    
    func testWorkflowURL() throws {
        // Test workflow URL generation
        let report = makeReport()
        XCTAssertEqual(report.workflowURL, "https://github.com/owner/repo/actions/runs/456789")
    }
    
    // MARK: - Build Notification Elements Tests
    
    func testBuildNotificationElementsReturnsString() throws {
        // Test that buildNotificationElements returns a formatted string
        let report = makeReport()
        let result = report.buildNotificationElements()
        XCTAssertTrue(result is String)
    }
    
    func testBuildNotificationElementsContainsPRLink() throws {
        // Test notification contains PR link in PR row using Slack format
        let report = makeReport()
        let result = report.buildNotificationElements()
        XCTAssertTrue(result.contains("*PR:* <https://github.com/owner/repo/pull/123|#123>"))
    }
    
    func testBuildNotificationElementsContainsProjectName() throws {
        // Test notification contains project name
        let report = makeReport()
        let result = report.buildNotificationElements()
        XCTAssertTrue(result.contains("*Project:*"))
        XCTAssertTrue(result.contains("my-project"))
    }
    
    func testBuildNotificationElementsContainsTask() throws {
        // Test notification contains task
        let report = makeReport()
        let result = report.buildNotificationElements()
        XCTAssertTrue(result.contains("*Task:*"))
        XCTAssertTrue(result.contains("Fix the login bug"))
    }
    
    func testBuildNotificationElementsContainsCost() throws {
        // Test notification contains cost
        let report = makeReport()
        let result = report.buildNotificationElements()
        XCTAssertTrue(result.contains("*Cost:*"))
        XCTAssertTrue(result.contains("$0.20"))
    }
    
    func testBuildNotificationElementsMatchesExpectedFormat() throws {
        // Test notification matches the expected Slack mrkdwn format
        let report = makeReport()
        let result = report.buildNotificationElements()
        
        let expected = (
            "*Repo:* owner/repo\n" +
            "*Project:* my-project\n" +
            "*PR:* <https://github.com/owner/repo/pull/123|#123>\n" +
            "*Task:* Fix the login bug\n" +
            "*Cost:* $0.20"
        )
        XCTAssertEqual(result, expected)
    }
    
    func testBuildNotificationElementsContainsRepo() throws {
        // Test notification contains repository name
        let report = makeReport()
        let result = report.buildNotificationElements()
        XCTAssertTrue(result.contains("*Repo:*"))
        XCTAssertTrue(result.contains("owner/repo"))
    }
    
    // MARK: - Build Comment Elements Tests
    
    func testBuildCommentElementsReturnsSection() throws {
        // Test that buildCommentElements returns a Section
        let report = makeReport()
        let result = report.buildCommentElements()
        XCTAssertTrue(result is Section)
    }
    
    func testBuildCommentElementsContainsCostHeader() throws {
        // Test comment contains cost breakdown header
        let report = makeReport()
        let result = report.buildCommentElements()
        let headers = result.elements.compactMap { $0 as? Header }
        let costHeader = headers.first { $0.text.contains("Cost") }
        XCTAssertNotNil(costHeader)
    }
    
    func testBuildCommentElementsContainsCostTable() throws {
        // Test comment contains cost table
        let report = makeReport()
        let result = report.buildCommentElements()
        let tables = result.elements.compactMap { $0 as? Table }
        XCTAssertGreaterThanOrEqual(tables.count, 1)
    }
    
    func testBuildCommentElementsContainsFooterWithWorkflowLink() throws {
        // Test comment contains footer with workflow link
        let report = makeReport()
        let result = report.buildCommentElements()
        let textBlocks = result.elements.compactMap { $0 as? TextBlock }
        let footer = textBlocks.first { $0.text.lowercased().contains("workflow") }
        XCTAssertNotNil(footer)
    }
    
    func testBuildCommentElementsIncludesSummaryWhenPresent() throws {
        // Test comment includes AI summary when provided
        let report = makeReportWithSummary()
        let result = report.buildCommentElements()
        let textBlocks = result.elements.compactMap { $0 as? TextBlock }
        let summary = textBlocks.first { $0.text.lowercased().contains("login") }
        XCTAssertNotNil(summary)
    }
    
    func testBuildCommentElementsIncludesDividerAfterSummary() throws {
        // Test comment has divider after summary
        let report = makeReportWithSummary()
        let result = report.buildCommentElements()
        let dividers = result.elements.compactMap { $0 as? Divider }
        XCTAssertGreaterThanOrEqual(dividers.count, 1)
    }
    
    func testBuildCommentElementsFormatsCorrectlyForMarkdown() throws {
        // Test comment renders correctly with MarkdownReportFormatter
        let report = makeReport()
        let elements = report.buildCommentElements()
        let formatter = MarkdownReportFormatter()
        let result = formatter.format(elements)
        
        XCTAssertTrue(result.contains("Cost"))
        XCTAssertTrue(result.contains("$0.15")) // main_cost
        XCTAssertTrue(result.contains("$0.05")) // summary_cost
        XCTAssertTrue(result.contains("$0.20")) // total_cost
    }
    
    // MARK: - Build Workflow Summary Elements Tests
    
    func testBuildWorkflowSummaryElementsReturnsSection() throws {
        // Test that buildWorkflowSummaryElements returns a Section
        let report = makeReport()
        let result = report.buildWorkflowSummaryElements()
        XCTAssertTrue(result is Section)
    }
    
    func testBuildWorkflowSummaryElementsContainsCompleteHeader() throws {
        // Test workflow summary contains completion header
        let report = makeReport()
        let result = report.buildWorkflowSummaryElements()
        let headers = result.elements.compactMap { $0 as? Header }
        let completeHeader = headers.first { $0.text.contains("Complete") }
        XCTAssertNotNil(completeHeader)
    }
    
    func testBuildWorkflowSummaryElementsContainsPRLink() throws {
        // Test workflow summary contains PR link
        let report = makeReport()
        let result = report.buildWorkflowSummaryElements()
        let labeledValues = result.elements.compactMap { $0 as? LabeledValue }
        let prLabel = labeledValues.first { $0.label == "PR" }
        XCTAssertNotNil(prLabel)
    }
    
    func testBuildWorkflowSummaryElementsContainsTaskWhenPresent() throws {
        // Test workflow summary contains task description
        let report = makeReport()
        let result = report.buildWorkflowSummaryElements()
        let labeledValues = result.elements.compactMap { $0 as? LabeledValue }
        let taskLabel = labeledValues.first { $0.label == "Task" }
        XCTAssertNotNil(taskLabel)
        
        // Check if task contains "login bug"
        if case .text(let value) = taskLabel!.value {
            XCTAssertTrue(value.contains("login bug"))
        } else {
            XCTFail("Expected text value for task label")
        }
    }
    
    func testBuildWorkflowSummaryElementsFormatsCorrectlyForMarkdown() throws {
        // Test workflow summary renders correctly with MarkdownReportFormatter
        let report = makeReport()
        let elements = report.buildWorkflowSummaryElements()
        let formatter = MarkdownReportFormatter()
        let result = formatter.format(elements)
        
        XCTAssertTrue(result.contains("ClaudeChain Complete"))
        XCTAssertTrue(result.contains("#123"))
        XCTAssertTrue(result.contains("Cost"))
    }
    
    // MARK: - Model Breakdown Tests
    
    func testNoModelBreakdownWhenNoModels() throws {
        // Test no model breakdown section when no models
        let report = makeReport()
        let result = report.buildCommentElements()
        // Should have exactly 1 table (cost summary), not model breakdown
        let tables = result.elements.compactMap { $0 as? Table }
        XCTAssertEqual(tables.count, 1)
    }
    
    func testIncludesModelBreakdownWhenModelsPresent() throws {
        // Test model breakdown included when models present
        let report = PullRequestCreatedReport(
            prNumber: "123",
            prURL: "https://github.com/owner/repo/pull/123",
            projectName: "my-project",
            task: "Fix bug",
            costBreakdown: makeMockCostBreakdownWithModels(),
            repo: "owner/repo",
            runID: "456789"
        )
        let result = report.buildCommentElements()
        
        // Should have nested section with model breakdown
        let sections = result.elements.compactMap { $0 as? Section }
        XCTAssertGreaterThanOrEqual(sections.count, 1)
        
        // Find model breakdown section
        let modelSection = sections[0]
        let headers = modelSection.elements.compactMap { $0 as? Header }
        let hasModelHeader = headers.contains { $0.text.contains("Model") }
        XCTAssertTrue(hasModelHeader)
    }
    
    // MARK: - Progress Line Tests
    
    func testNoProgressInfo() throws {
        // Should not include progress line when no progress info
        let report = PullRequestCreatedReport(
            prNumber: "123",
            prURL: "https://github.com/owner/repo/pull/123",
            projectName: "my-project",
            task: "Fix bug",
            costBreakdown: makeMockCostBreakdown(),
            repo: "owner/repo",
            runID: "456789"
        )
        let result = report.buildNotificationElements()
        XCTAssertFalse(result.contains("Progress"))
    }
    
    func testProgressLineSingleSlot() throws {
        // Should show merged count but not slots when maxOpenPRs is 1
        let report = PullRequestCreatedReport(
            prNumber: "123",
            prURL: "https://github.com/owner/repo/pull/123",
            projectName: "my-project",
            task: "Fix bug",
            costBreakdown: makeMockCostBreakdown(),
            repo: "owner/repo",
            runID: "456789",
            progressInfo: [
                "tasks_completed": 5,
                "tasks_total": 26,
                "max_open_prs": 1,
                "open_pr_count": 0
            ]
        )
        let result = report.buildNotificationElements()
        XCTAssertTrue(result.contains("5/26 merged"))
        XCTAssertFalse(result.contains("async slots"))
    }
    
    func testProgressLineMultipleSlots() throws {
        // Should show merged count and async slots when maxOpenPRs > 1
        let report = PullRequestCreatedReport(
            prNumber: "123",
            prURL: "https://github.com/owner/repo/pull/123",
            projectName: "my-project",
            task: "Fix bug",
            costBreakdown: makeMockCostBreakdown(),
            repo: "owner/repo",
            runID: "456789",
            progressInfo: [
                "tasks_completed": 5,
                "tasks_total": 26,
                "max_open_prs": 3,
                "open_pr_count": 1
            ]
        )
        let result = report.buildNotificationElements()
        XCTAssertTrue(result.contains("5/26 merged"))
        XCTAssertTrue(result.contains("2 of 3 async slots in use"))
    }
    
    func testProgressLineAccountsForNewPR() throws {
        // Should add 1 to open_pr_count since this PR was just created
        let report = PullRequestCreatedReport(
            prNumber: "123",
            prURL: "https://github.com/owner/repo/pull/123",
            projectName: "my-project",
            task: "Fix bug",
            costBreakdown: makeMockCostBreakdown(),
            repo: "owner/repo",
            runID: "456789",
            progressInfo: [
                "tasks_completed": 0,
                "tasks_total": 10,
                "max_open_prs": 3,
                "open_pr_count": 0
            ]
        )
        let result = report.buildNotificationElements()
        // open_pr_count=0 but this PR was just created, so should show 1
        XCTAssertTrue(result.contains("1 of 3 async slots in use"))
    }
}