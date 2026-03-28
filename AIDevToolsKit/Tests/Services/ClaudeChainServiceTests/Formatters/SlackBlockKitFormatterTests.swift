/// Tests for Slack Block Kit formatter
import XCTest
import Foundation
@testable import ClaudeChainService

class SlackBlockKitFormatterTests: XCTestCase {
    
    // MARK: - Block Builder Function Tests
    
    func testHeaderBlockStructure() throws {
        // Header block uses plain_text type as required by Slack
        let result = headerBlock(text: "Test Title")
        
        XCTAssertEqual(result["type"] as? String, "header")
        let textDict = result["text"] as? [String: Any]
        XCTAssertEqual(textDict?["type"] as? String, "plain_text")
        XCTAssertEqual(textDict?["text"] as? String, "Test Title")
        XCTAssertEqual(textDict?["emoji"] as? Bool, true)
    }
    
    func testHeaderBlockTruncatesLongText() throws {
        // Header text is truncated to 150 characters
        let longText = String(repeating: "x", count: 200)
        let result = headerBlock(text: longText)
        
        let textDict = result["text"] as? [String: Any]
        XCTAssertEqual((textDict?["text"] as? String)?.count, 150)
    }
    
    func testContextBlockStructure() throws {
        // Context block uses mrkdwn type
        let result = contextBlock("Test context")
        
        XCTAssertEqual(result["type"] as? String, "context")
        let elements = result["elements"] as? [[String: Any]]
        XCTAssertEqual(elements?.count, 1)
        XCTAssertEqual(elements?[0]["type"] as? String, "mrkdwn")
        XCTAssertEqual(elements?[0]["text"] as? String, "Test context")
    }
    
    func testSectionBlockWithTextOnly() throws {
        // Section block with just text
        let result = sectionBlock("*Bold text*")
        
        XCTAssertEqual(result["type"] as? String, "section")
        let textDict = result["text"] as? [String: Any]
        XCTAssertEqual(textDict?["type"] as? String, "mrkdwn")
        XCTAssertEqual(textDict?["text"] as? String, "*Bold text*")
        XCTAssertNil(result["fields"])
    }
    
    func testSectionBlockWithFields() throws {
        // Section block with text and fields
        let result = sectionBlock("Main text", fields: ["Field 1", "Field 2"])
        
        XCTAssertEqual(result["type"] as? String, "section")
        let textDict = result["text"] as? [String: Any]
        XCTAssertEqual(textDict?["text"] as? String, "Main text")
        
        let fields = result["fields"] as? [[String: Any]]
        XCTAssertEqual(fields?.count, 2)
        XCTAssertEqual(fields?[0]["type"] as? String, "mrkdwn")
        XCTAssertEqual(fields?[0]["text"] as? String, "Field 1")
    }
    
    func testSectionBlockLimitsFieldsTo10() throws {
        // Section fields are limited to 10 per Slack API requirements
        let fields = (0..<15).map { "Field \($0)" }
        let result = sectionBlock("Text", fields: fields)
        
        let resultFields = result["fields"] as? [[String: Any]]
        XCTAssertEqual(resultFields?.count, 10)
    }
    
    func testSectionFieldsBlockStructure() throws {
        // Section fields block has no main text
        let result = sectionFieldsBlock(fields: ["Field 1", "Field 2"])
        
        XCTAssertEqual(result["type"] as? String, "section")
        XCTAssertNil(result["text"])
        
        let fields = result["fields"] as? [[String: Any]]
        XCTAssertEqual(fields?.count, 2)
    }
    
    func testSectionFieldsBlockLimitsTo10() throws {
        // Section fields block limited to 10 fields
        let fields = (0..<15).map { "Field \($0)" }
        let result = sectionFieldsBlock(fields: fields)
        
        let resultFields = result["fields"] as? [[String: Any]]
        XCTAssertEqual(resultFields?.count, 10)
    }
    
    func testDividerBlockStructure() throws {
        // Divider block has correct type
        let result = dividerBlock()
        
        XCTAssertEqual(result["type"] as? String, "divider")
        XCTAssertEqual(result.count, 1) // Only has type field
    }
    
    // MARK: - Progress Bar Tests
    
    func testProgressBar0Percent() throws {
        // 0% shows all empty blocks
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatProjectBlocks(
            projectName: "test",
            merged: 0,
            total: 10,
            costUSD: 0.0
        )
        
        // Check the progress bar in the section block
        let sectionText = (result[0]["text"] as? [String: Any])?["text"] as? String ?? ""
        XCTAssertTrue(sectionText.contains("░░░░░░░░░░ 0%"))
    }
    
    func testProgressBar50Percent() throws {
        // 50% shows half filled
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatProjectBlocks(
            projectName: "test",
            merged: 5,
            total: 10,
            costUSD: 0.0
        )
        
        // Check the progress bar in the section block
        let sectionText = (result[0]["text"] as? [String: Any])?["text"] as? String ?? ""
        XCTAssertTrue(sectionText.contains("█████░░░░░ 50%"))
    }
    
    func testProgressBar100Percent() throws {
        // 100% shows all filled
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatProjectBlocks(
            projectName: "test",
            merged: 10,
            total: 10,
            costUSD: 0.0
        )
        
        // Check the progress bar in the section block
        let sectionText = (result[0]["text"] as? [String: Any])?["text"] as? String ?? ""
        XCTAssertTrue(sectionText.contains("██████████ 100%"))
    }
    
    func testProgressBarSmallPercentageShowsAtLeastOne() throws {
        // Small non-zero percentages show at least one filled block
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatProjectBlocks(
            projectName: "test",
            merged: 1,
            total: 20,
            costUSD: 0.0
        )
        
        // Check the progress bar in the section block
        let sectionText = (result[0]["text"] as? [String: Any])?["text"] as? String ?? ""
        XCTAssertTrue(sectionText.contains("█"))
        XCTAssertTrue(sectionText.contains("5%"))
    }
    
    // MARK: - SlackBlockKitFormatter Tests
    
    func testBuildMessageStructure() throws {
        // Build message includes text and blocks
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let blocks = [["type": "divider"]]
        let result = formatter.buildMessage(blocks: blocks, fallbackText: "Test")
        
        XCTAssertEqual(result["text"] as? String, "Test")
        let resultBlocks = result["blocks"] as? [[String: Any]] ?? []
        XCTAssertEqual(resultBlocks.count, blocks.count)
        if !resultBlocks.isEmpty && !blocks.isEmpty {
            XCTAssertEqual(resultBlocks[0]["type"] as? String, blocks[0]["type"] as? String)
        }
    }
    
    func testFormatHeaderBlocksWithRepo() throws {
        // Header shows Chains with repo name
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatHeaderBlocks()
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0]["type"] as? String, "section")
        let textDict = result[0]["text"] as? [String: Any]
        XCTAssertTrue((textDict?["text"] as? String)?.contains("🔗 *Chains:* owner/repo") ?? false)
    }
    
    func testFormatHeaderBlocksWithoutRepo() throws {
        // Header shows just Chains when no repo
        let formatter = SlackBlockKitFormatter(repo: "")
        let result = formatter.formatHeaderBlocks()
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0]["type"] as? String, "section")
        let textDict = result[0]["text"] as? [String: Any]
        XCTAssertEqual(textDict?["text"] as? String, "🔗 *Chains*")
    }
    
    // MARK: - Project Block Tests
    
    func testProjectShowsCheckmarkWhenComplete() throws {
        // 100% complete projects show ✅ in stats line
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatProjectBlocks(
            projectName: "test-project",
            merged: 10,
            total: 10,
            costUSD: 5.00
        )
        
        // Checkmark is in the context/stats line
        let contextElements = result[1]["elements"] as? [[String: Any]]
        let contextText = contextElements?[0]["text"] as? String ?? ""
        XCTAssertTrue(contextText.contains("✅"))
        
        // Project name is in the section text
        let sectionText = (result[0]["text"] as? [String: Any])?["text"] as? String ?? ""
        XCTAssertTrue(sectionText.contains("*test-project*"))
    }
    
    func testProjectShowsSpinnerWhenHasOpenPRs() throws {
        // Projects with open PRs show 🔄 in stats line
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatProjectBlocks(
            projectName: "test-project",
            merged: 5,
            total: 10,
            costUSD: 5.00,
            openPRs: [["number": 1, "title": "Test PR", "age_days": 0]]
        )
        
        let contextElements = result[1]["elements"] as? [[String: Any]]
        let contextText = contextElements?[0]["text"] as? String ?? ""
        XCTAssertTrue(contextText.contains("🔄"))
    }
    
    func testProjectShowsWarningWhenStalled() throws {
        // Projects with tasks remaining but no open PRs show ⚠️ in stats line
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatProjectBlocks(
            projectName: "test-project",
            merged: 5,
            total: 10,
            costUSD: 5.00
        )
        
        let contextElements = result[1]["elements"] as? [[String: Any]]
        let contextText = contextElements?[0]["text"] as? String ?? ""
        XCTAssertTrue(contextText.contains("⚠️"))
    }
    
    func testProjectShowsProgressBar() throws {
        // Project blocks include progress bar
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatProjectBlocks(
            projectName: "test-project",
            merged: 5,
            total: 10,
            costUSD: 5.00
        )
        
        let sectionText = (result[0]["text"] as? [String: Any])?["text"] as? String ?? ""
        XCTAssertTrue(sectionText.contains("█"))
        XCTAssertTrue(sectionText.contains("50%"))
    }
    
    func testProjectShowsStatsContext() throws {
        // Project blocks include merged count and cost
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatProjectBlocks(
            projectName: "test-project",
            merged: 5,
            total: 10,
            costUSD: 15.50
        )
        
        let contextElements = result[1]["elements"] as? [[String: Any]]
        let contextText = contextElements?[0]["text"] as? String ?? ""
        XCTAssertTrue(contextText.contains("5/10"))
        XCTAssertTrue(contextText.contains("merged"))
        XCTAssertTrue(contextText.contains("$15.50"))
    }
    
    func testProjectShowsOpenPRsWithLinks() throws {
        // Open PRs are shown as clickable links with Open prefix
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatProjectBlocks(
            projectName: "test-project",
            merged: 5,
            total: 10,
            costUSD: 5.00,
            openPRs: [[
                "number": 42,
                "title": "Fix bug",
                "url": "https://github.com/owner/repo/pull/42",
                "age_days": 3
            ]]
        )
        
        // Should have section, context, PR section, divider
        XCTAssertEqual(result.count, 4)
        let prSectionText = (result[2]["text"] as? [String: Any])?["text"] as? String ?? ""
        XCTAssertTrue(prSectionText.contains("<https://github.com/owner/repo/pull/42|#42 Fix bug>"))
        XCTAssertTrue(prSectionText.contains("(Open 3d)"))
    }
    
    func testProjectShowsWarningForStalePRs() throws {
        // PRs older than 5 days show ⚠️
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatProjectBlocks(
            projectName: "test-project",
            merged: 5,
            total: 10,
            costUSD: 5.00,
            openPRs: [[
                "number": 42,
                "title": "Old PR",
                "age_days": 7
            ]]
        )
        
        let prSectionText = (result[2]["text"] as? [String: Any])?["text"] as? String ?? ""
        XCTAssertTrue(prSectionText.contains("⚠️"))
    }
    
    func testProjectNoWarningForFreshPRs() throws {
        // PRs under 5 days don't show ⚠️
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatProjectBlocks(
            projectName: "test-project",
            merged: 5,
            total: 10,
            costUSD: 5.00,
            openPRs: [[
                "number": 42,
                "title": "Fresh PR",
                "age_days": 2
            ]]
        )
        
        let prSectionText = (result[2]["text"] as? [String: Any])?["text"] as? String ?? ""
        XCTAssertFalse(prSectionText.contains("⚠️"))
    }
    
    func testProjectBuildsPreURLFromRepo() throws {
        // PR URLs are built from repo when not provided
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatProjectBlocks(
            projectName: "test-project",
            merged: 5,
            total: 10,
            costUSD: 5.00,
            openPRs: [[
                "number": 42,
                "title": "Test PR",
                "age_days": 1
            ]]
        )
        
        let prSectionText = (result[2]["text"] as? [String: Any])?["text"] as? String ?? ""
        XCTAssertTrue(prSectionText.contains("https://github.com/owner/repo/pull/42"))
    }
    
    func testProjectEndsWithDivider() throws {
        // Each project block ends with a divider
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatProjectBlocks(
            projectName: "test-project",
            merged: 5,
            total: 10,
            costUSD: 5.00
        )
        
        XCTAssertEqual(result.last?["type"] as? String, "divider")
    }
    
    // MARK: - Leaderboard Tests
    
    func testLeaderboardReturnsEmptyForNoEntries() throws {
        // Empty entries returns empty list
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatLeaderboardBlocks(entries: [])
        XCTAssertEqual(result.count, 0)
    }
    
    func testLeaderboardShowsMedalsForTop3() throws {
        // Top 3 entries get medal emojis
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let entries = [
            ["username": "alice", "merged": 10],
            ["username": "bob", "merged": 8],
            ["username": "charlie", "merged": 6],
            ["username": "dave", "merged": 4]
        ]
        let result = formatter.formatLeaderboardBlocks(entries: entries)
        
        // Find the fields section
        let fieldsBlock = result[1]
        let fields = fieldsBlock["fields"] as? [[String: Any]] ?? []
        let fieldsText = fields.map { $0["text"] as? String ?? "" }.joined(separator: " ")
        
        XCTAssertTrue(fieldsText.contains("🥇"))
        XCTAssertTrue(fieldsText.contains("🥈"))
        XCTAssertTrue(fieldsText.contains("🥉"))
        XCTAssertTrue(fieldsText.contains("4.")) // 4th place gets number
    }
    
    func testLeaderboardUsesSectionFields() throws {
        // Leaderboard uses 2-column section fields layout
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let entries = [
            ["username": "alice", "merged": 10],
            ["username": "bob", "merged": 8]
        ]
        let result = formatter.formatLeaderboardBlocks(entries: entries)
        
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0]["type"] as? String, "section") // Header
        XCTAssertEqual(result[1]["type"] as? String, "section") // Fields
        XCTAssertNotNil(result[1]["fields"])
    }
    
    func testLeaderboardLimitsTo6Entries() throws {
        // Leaderboard limited to 6 entries to stay under 10 fields
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let entries = (0..<10).map { ["username": "user\($0)", "merged": 10 - $0] }
        let result = formatter.formatLeaderboardBlocks(entries: entries)
        
        let fieldsBlock = result[1]
        let fields = fieldsBlock["fields"] as? [[String: Any]] ?? []
        XCTAssertEqual(fields.count, 6)
    }
    
    // MARK: - Warning Tests
    
    func testWarningsReturnsEmptyForNoWarnings() throws {
        // Empty warnings returns empty list
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatWarningsBlocks(warnings: [])
        XCTAssertEqual(result.count, 0)
    }
    
    func testWarningsShowsHeaderAndItems() throws {
        // Warnings include header and item list
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let warnings = [[
            "project_name": "test-project",
            "items": ["#42 (7d, stale)", "#43 (orphaned)"]
        ]]
        let result = formatter.formatWarningsBlocks(warnings: warnings)
        
        XCTAssertEqual(result.count, 2)
        let headerText = (result[0]["text"] as? [String: Any])?["text"] as? String ?? ""
        XCTAssertTrue(headerText.contains("⚠️ Needs Attention"))
        
        let itemText = (result[1]["text"] as? [String: Any])?["text"] as? String ?? ""
        XCTAssertTrue(itemText.contains("test-project"))
        XCTAssertTrue(itemText.contains("#42"))
    }
    
    // MARK: - Error Notification Tests
    
    func testErrorNotificationStructure() throws {
        // Error notification includes all required blocks
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatErrorNotification(
            projectName: "test-project",
            taskDescription: "Implement feature X",
            errorMessage: "File not found",
            runURL: "https://github.com/owner/repo/actions/runs/123"
        )
        
        XCTAssertNotNil(result["text"])
        XCTAssertNotNil(result["blocks"])
        XCTAssertEqual(result["text"] as? String, "ClaudeChain task failed: test-project")
    }
    
    func testErrorNotificationHeader() throws {
        // Error notification has correct header
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatErrorNotification(
            projectName: "test-project",
            taskDescription: "Implement feature X",
            errorMessage: "Something went wrong",
            runURL: "https://github.com/owner/repo/actions/runs/123"
        )
        
        let blocks = result["blocks"] as? [[String: Any]] ?? []
        let headerBlock = blocks[0]
        XCTAssertEqual(headerBlock["type"] as? String, "header")
        let headerText = (headerBlock["text"] as? [String: Any])?["text"] as? String ?? ""
        XCTAssertTrue(headerText.contains("Task Failed"))
        XCTAssertTrue(headerText.contains("❌"))
    }
    
    func testErrorNotificationIncludesProjectAndTask() throws {
        // Error notification shows project name and task description
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatErrorNotification(
            projectName: "my-project",
            taskDescription: "Fix the bug",
            errorMessage: "Error occurred",
            runURL: "https://github.com/owner/repo/actions/runs/123"
        )
        
        let blocks = result["blocks"] as? [[String: Any]] ?? []
        let sectionBlock = blocks[1]
        XCTAssertEqual(sectionBlock["type"] as? String, "section")
        let sectionText = (sectionBlock["text"] as? [String: Any])?["text"] as? String ?? ""
        XCTAssertTrue(sectionText.contains("my-project"))
        XCTAssertTrue(sectionText.contains("Fix the bug"))
    }
    
    func testErrorNotificationIncludesErrorMessage() throws {
        // Error notification includes the error message in code block
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatErrorNotification(
            projectName: "test-project",
            taskDescription: "Implement feature X",
            errorMessage: "Something went wrong",
            runURL: "https://github.com/owner/repo/actions/runs/123"
        )
        
        let blocks = result["blocks"] as? [[String: Any]] ?? []
        let errorBlock = blocks[2]
        XCTAssertEqual(errorBlock["type"] as? String, "section")
        let errorText = (errorBlock["text"] as? [String: Any])?["text"] as? String ?? ""
        XCTAssertTrue(errorText.contains("```Something went wrong```"))
    }
    
    func testErrorNotificationTruncatesLongError() throws {
        // Long error messages are truncated
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let longError = String(repeating: "x", count: 600)
        let result = formatter.formatErrorNotification(
            projectName: "test-project",
            taskDescription: "Implement feature X",
            errorMessage: longError,
            runURL: "https://github.com/owner/repo/actions/runs/123"
        )
        
        let blocks = result["blocks"] as? [[String: Any]] ?? []
        let errorBlock = blocks[2]
        let errorText = (errorBlock["text"] as? [String: Any])?["text"] as? String ?? ""
        // Should be truncated to 500 chars + "..."
        XCTAssertTrue(errorText.contains("..."))
        XCTAssertLessThan(errorText.count, 600)
    }
    
    func testErrorNotificationIncludesRunURL() throws {
        // Error notification includes link to workflow run
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatErrorNotification(
            projectName: "test-project",
            taskDescription: "Implement feature X",
            errorMessage: "Error occurred",
            runURL: "https://github.com/owner/repo/actions/runs/123"
        )
        
        let blocks = result["blocks"] as? [[String: Any]] ?? []
        let contextBlock = blocks.last!
        XCTAssertEqual(contextBlock["type"] as? String, "context")
        let contextElements = contextBlock["elements"] as? [[String: Any]]
        let contextText = contextElements?[0]["text"] as? String ?? ""
        XCTAssertTrue(contextText.contains("https://github.com/owner/repo/actions/runs/123"))
        XCTAssertTrue(contextText.contains("View workflow run"))
    }
    
    func testErrorNotificationWithoutErrorMessage() throws {
        // Error notification works when error_message is empty
        let formatter = SlackBlockKitFormatter(repo: "owner/repo")
        let result = formatter.formatErrorNotification(
            projectName: "test-project",
            taskDescription: "Implement feature X",
            errorMessage: "",
            runURL: "https://github.com/owner/repo/actions/runs/123"
        )
        
        let blocks = result["blocks"] as? [[String: Any]] ?? []
        // Should have header, project/task section, and context (no error block)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0]["type"] as? String, "header")
        XCTAssertEqual(blocks[1]["type"] as? String, "section")
        XCTAssertEqual(blocks[2]["type"] as? String, "context")
    }
}