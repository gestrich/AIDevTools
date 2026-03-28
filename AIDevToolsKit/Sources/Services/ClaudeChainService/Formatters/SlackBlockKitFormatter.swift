/// Slack Block Kit formatter for statistics reports.
///
/// Generates Slack Block Kit JSON structures instead of plain mrkdwn text.
/// Block Kit provides richer formatting with native Slack components:
/// - Header blocks for titles
/// - Section blocks for content with optional fields
/// - Context blocks for metadata
/// - Divider blocks for visual separation
///
/// Reference: https://api.slack.com/block-kit
import Foundation

/// Formatter that produces Slack Block Kit JSON structures.
///
/// Unlike SlackReportFormatter which outputs mrkdwn strings, this formatter
/// generates the JSON block structures needed for Block Kit messages.
public class SlackBlockKitFormatter {
    public let repo: String
    
    /// Initialize the formatter.
    ///
    /// - Parameter repo: GitHub repository (owner/name) for building PR URLs
    public init(repo: String) {
        self.repo = repo
    }
    
    // MARK: - Public API - Message Building
    
    /// Build the complete Slack message payload.
    ///
    /// - Parameters:
    ///   - blocks: List of Block Kit blocks
    ///   - fallbackText: Text shown in notifications/previews
    /// - Returns: Complete Slack message payload with text and blocks
    public func buildMessage(blocks: [[String: Any]], fallbackText: String = "ClaudeChain Stats") -> [String: Any] {
        return [
            "text": fallbackText,
            "blocks": blocks
        ]
    }
    
    /// Generate header blocks for the Chains section.
    ///
    /// Uses section block with bold text to match leaderboard style.
    ///
    /// - Returns: List of Block Kit blocks for the header
    public func formatHeaderBlocks() -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        if !repo.isEmpty {
            blocks.append(sectionBlock("🔗 *Chains:* \(repo)"))
        } else {
            blocks.append(sectionBlock("🔗 *Chains*"))
        }
        return blocks
    }
    
    // MARK: - Public API - Content Formatting
    
    /// Generate Block Kit blocks for a single project.
    ///
    /// - Parameters:
    ///   - projectName: Name of the project
    ///   - merged: Number of merged PRs/tasks
    ///   - total: Total number of tasks
    ///   - costUSD: Total cost for this project
    ///   - openPRs: List of open PRs with keys: number, title, url, age_days
    /// - Returns: List of Block Kit blocks for the project
    public func formatProjectBlocks(
        projectName: String,
        merged: Int,
        total: Int,
        costUSD: Double,
        openPRs: [[String: Any]]? = nil
    ) -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        
        let percentComplete: Double = total > 0 ? (Double(merged) / Double(total) * 100) : 0
        let isComplete = merged == total && total > 0
        let hasOpenPRs = !(openPRs?.isEmpty ?? true)
        
        // Determine status indicator
        let status: String
        if isComplete {
            status = "✅"
        } else if hasOpenPRs {
            status = "🔄"
        } else {
            status = "⚠️"
        }
        
        let name = "Project: *\(projectName)*"
        let progressBar = generateProgressBar(percentage: percentComplete)
        
        blocks.append(sectionBlock("\(name)\n\(progressBar)"))
        
        let costStr = costUSD > 0 ? Formatting.formatUSD(costUSD) : "$0.00"
        // Pad numbers for alignment (right-align merged, left-align total)
        let progressText = String(format: "%2d/%-2d", merged, total)
        blocks.append(contextBlock("\(status)  \(progressText) merged  •  💰 \(costStr)"))
        
        if let openPRs = openPRs, !openPRs.isEmpty {
            var prLines: [String] = []
            for pr in openPRs {
                var url = pr["url"] as? String
                let number = pr["number"] as? Int ?? 0
                let title = pr["title"] as? String ?? ""
                let ageDays = pr["age_days"] as? Int ?? 0
                let ageFormatted = pr["age_formatted"] as? String ?? "\(ageDays)d"
                
                if url == nil && !repo.isEmpty {
                    url = buildPRURL(number: number)
                }
                
                let line: String
                if let url = url {
                    line = "<\(url)|#\(number) \(title)> (Open \(ageFormatted))"
                } else {
                    line = "#\(number) \(title) (Open \(ageFormatted))"
                }
                
                let finalLine = ageDays >= 5 ? line + " ⚠️" : line
                prLines.append(finalLine)
            }
            
            blocks.append(sectionBlock(prLines.joined(separator: "\n")))
        }
        
        blocks.append(dividerBlock())
        return blocks
    }
    
    /// Generate Block Kit blocks for the leaderboard.
    ///
    /// - Parameter entries: List of leaderboard entries with keys: username, merged
    /// - Returns: List of Block Kit blocks for the leaderboard
    public func formatLeaderboardBlocks(entries: [[String: Any]]) -> [[String: Any]] {
        if entries.isEmpty {
            return []
        }
        
        var blocks: [[String: Any]] = []
        let medals = ["🥇", "🥈", "🥉"]
        
        blocks.append(sectionBlock("*🏆 Leaderboard*"))
        
        var fields: [String] = []
        let entriesToShow = Array(entries.prefix(6))
        
        for (i, entry) in entriesToShow.enumerated() {
            let username = entry["username"] as? String ?? ""
            let merged = entry["merged"] as? Int ?? 0
            let medal = i < 3 ? medals[i] : "\(i + 1)."
            fields.append("\(medal) *\(username)*  •  \(merged) merged")
        }
        
        if !fields.isEmpty {
            blocks.append(sectionFieldsBlock(fields: fields))
        }
        
        return blocks
    }
    
    /// Generate Block Kit blocks for warnings/attention section.
    ///
    /// - Parameter warnings: List of warning items with keys: project_name, items
    /// - Returns: List of Block Kit blocks for warnings
    public func formatWarningsBlocks(warnings: [[String: Any]]) -> [[String: Any]] {
        if warnings.isEmpty {
            return []
        }
        
        var blocks: [[String: Any]] = []
        blocks.append(sectionBlock("*⚠️ Needs Attention*"))
        
        for warning in warnings {
            let projectName = warning["project_name"] as? String ?? ""
            let items = warning["items"] as? [String] ?? []
            
            if !items.isEmpty {
                let content = "*\(projectName)*\n" + items.map { "• \($0)" }.joined(separator: "\n")
                blocks.append(sectionBlock(content))
            }
        }
        
        return blocks
    }
    
    /// Generate Slack Block Kit payload for error notification.
    ///
    /// Creates an error-styled Slack message when Claude Code fails to complete a task.
    ///
    /// - Parameters:
    ///   - projectName: Name of the project
    ///   - taskDescription: Description of the task that failed
    ///   - errorMessage: Error message from Claude Code
    ///   - runURL: URL to the GitHub Actions run
    /// - Returns: Complete Slack message payload with error styling
    public func formatErrorNotification(
        projectName: String,
        taskDescription: String,
        errorMessage: String,
        runURL: String
    ) -> [String: Any] {
        var blocks: [[String: Any]] = []
        
        // Header with error emoji
        blocks.append(headerBlock(text: "Task Failed ❌"))
        
        // Project and task info
        let content = "*Project:* \(projectName)\n*Task:* \(taskDescription)"
        blocks.append(sectionBlock(content))
        
        // Error message
        if !errorMessage.isEmpty {
            // Truncate long error messages
            let truncatedError = errorMessage.count > 500 ? String(errorMessage.prefix(500)) + "..." : errorMessage
            blocks.append(sectionBlock("*Error:*\n```\(truncatedError)```"))
        }
        
        // Footer with link to action run
        blocks.append(contextBlock("<\(runURL)|View workflow run>"))
        
        return buildMessage(blocks: blocks, fallbackText: "ClaudeChain task failed: \(projectName)")
    }
    
    // MARK: - Private Helpers
    
    /// Construct GitHub PR URL from repo and PR number.
    ///
    /// - Parameter number: The pull request number
    /// - Returns: Full GitHub PR URL
    private func buildPRURL(number: Int) -> String {
        return "https://github.com/\(repo)/pull/\(number)"
    }
}

// MARK: - Block Builder Functions

/// Create a header block.
///
/// - Parameter text: Header text (plain text only, max 150 chars)
/// - Returns: Slack header block structure
public func headerBlock(text: String) -> [String: Any] {
    let truncatedText = String(text.prefix(150))
    return [
        "type": "header",
        "text": [
            "type": "plain_text",
            "text": truncatedText,
            "emoji": true
        ]
    ]
}

/// Create a context block with mrkdwn text.
///
/// - Parameter text: Context text (supports mrkdwn formatting)
/// - Returns: Slack context block structure
public func contextBlock(_ text: String) -> [String: Any] {
    return [
        "type": "context",
        "elements": [
            [
                "type": "mrkdwn",
                "text": text
            ]
        ]
    ]
}

/// Create a section block with optional fields.
///
/// - Parameters:
///   - text: Main section text (supports mrkdwn)
///   - fields: Optional list of field texts (max 10, displayed in 2-column grid)
/// - Returns: Slack section block structure
public func sectionBlock(_ text: String, fields: [String]? = nil) -> [String: Any] {
    var block: [String: Any] = [
        "type": "section",
        "text": [
            "type": "mrkdwn",
            "text": text
        ]
    ]
    
    if let fields = fields {
        block["fields"] = Array(fields.prefix(10)).map { field in
            [
                "type": "mrkdwn",
                "text": field
            ]
        }
    }
    
    return block
}

/// Create a section block with only fields (no main text).
///
/// - Parameter fields: List of field texts (max 10, displayed in 2-column grid)
/// - Returns: Slack section block structure with fields only
public func sectionFieldsBlock(fields: [String]) -> [String: Any] {
    return [
        "type": "section",
        "fields": Array(fields.prefix(10)).map { field in
            [
                "type": "mrkdwn",
                "text": field
            ]
        }
    ]
}

/// Create a divider block.
///
/// - Returns: Slack divider block structure
public func dividerBlock() -> [String: Any] {
    return ["type": "divider"]
}

// MARK: - Footer Helpers

/// Format the footer text for Slack notifications.
///
/// Creates consistent "Generated by ClaudeChain" footer with optional elapsed time.
///
/// - Parameters:
///   - runURL: URL to GitHub Actions run
///   - elapsedSeconds: Optional elapsed time in seconds
/// - Returns: Formatted mrkdwn string like "Generated by <url|ClaudeChain> (41.8s)"
public func formatFooterText(runURL: String, elapsedSeconds: Double? = nil) -> String {
    if let elapsedSeconds = elapsedSeconds {
        return "Generated by <\(runURL)|ClaudeChain> (\(String(format: "%.1f", elapsedSeconds))s)"
    }
    return "Generated by <\(runURL)|ClaudeChain>"
}

// MARK: - Private Module Helpers

/// Generate Unicode progress bar string.
///
/// - Parameters:
///   - percentage: Completion percentage (0-100)
///   - width: Number of characters for the bar
/// - Returns: String like "████████░░ 80%"
private func generateProgressBar(percentage: Double, width: Int = 10) -> String {
    var filled = Int((percentage / 100) * Double(width))
    if percentage > 0 && filled == 0 {
        filled = 1
    }
    let empty = width - filled
    let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
    return "\(bar) \(String(format: "%.0f", percentage))%"
}