/// Domain model for PR creation reports.
///
/// PullRequestCreatedReport consolidates all PR-related formatting into a single
/// domain model that can be rendered for Slack notifications, PR comments,
/// and workflow summaries using the formatter pattern.
import Foundation

/// Domain model for PR creation reports.
///
/// Holds all data needed to generate PR notifications, comments, and summaries.
/// Provides element-building methods for each output format.
public struct PullRequestCreatedReport {
    /// Pull request number
    public let prNumber: String
    
    /// Full URL to the pull request
    public let prURL: String
    
    /// Name of the project
    public let projectName: String
    
    /// Task description
    public let task: String
    
    /// Cost breakdown with per-model data
    public let costBreakdown: CostBreakdown
    
    /// Repository in format owner/repo
    public let repo: String
    
    /// Workflow run ID
    public let runID: String
    
    /// Optional AI-generated summary content
    public let summaryContent: String?
    
    public let assignee: String?
    
    /// {tasks_completed, tasks_total, max_open_prs, open_pr_count}
    public let progressInfo: [String: Any]?
    
    public init(
        prNumber: String,
        prURL: String,
        projectName: String,
        task: String,
        costBreakdown: CostBreakdown,
        repo: String,
        runID: String,
        summaryContent: String? = nil,
        assignee: String? = nil,
        progressInfo: [String: Any]? = nil
    ) {
        self.prNumber = prNumber
        self.prURL = prURL
        self.projectName = projectName
        self.task = task
        self.costBreakdown = costBreakdown
        self.repo = repo
        self.runID = runID
        self.summaryContent = summaryContent
        self.assignee = assignee
        self.progressInfo = progressInfo
    }
    
    /// Generate the workflow run URL.
    public var workflowURL: String {
        return "https://github.com/\(repo)/actions/runs/\(runID)"
    }
    
    // MARK: - Element Building Methods
    
    /// Build formatted Slack notification message.
    ///
    /// Returns a pre-formatted string to match the exact Slack message format
    /// with specific blank line placement. Note: The "PR Created" header is
    /// rendered separately in action.yml using Block Kit header block.
    ///
    /// - Returns: Formatted Slack notification string (body content only, no title).
    public func buildNotificationElements() -> String {
        let formatter = SlackReportFormatter()
        
        // Build body content - Repo first for context, then Project and PR
        var lines = [
            formatter.formatLabeledValue(LabeledValue(label: "Repo", value: .text(repo))),
            formatter.formatLabeledValue(LabeledValue(label: "Project", value: .text(projectName))),
            formatter.formatLabeledValue(LabeledValue(label: "PR", value: .link(Link(text: "#\(prNumber)", url: prURL)))),
        ]
        
        // Add assignee if present
        if let assignee = assignee {
            lines.append(formatter.formatLabeledValue(LabeledValue(label: "Assignee", value: .text("@\(assignee)"))))
        }
        
        lines.append(contentsOf: [
            formatter.formatLabeledValue(LabeledValue(label: "Task", value: .text(task))),
            formatter.formatLabeledValue(LabeledValue(label: "Cost", value: .text(Formatting.formatUSD(costBreakdown.totalCost)))),
        ])
        
        // Add progress line if available
        if let progressLine = formatProgressLine() {
            lines.append(progressLine)
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Build report elements for PR comment.
    ///
    /// Includes optional AI summary and detailed cost breakdown.
    ///
    /// - Returns: Section containing elements for GitHub PR comment.
    public func buildCommentElements() -> Section {
        let section = Section()
        
        // Include AI summary if present
        if let summaryContent = summaryContent {
            section.add(TextBlock(text: summaryContent))
            section.add(Divider())
        }
        
        // Cost breakdown header
        section.add(Header(text: "💰 Cost Breakdown", level: 2))
        section.add(TextBlock(text: "This PR was generated using Claude Code with the following costs:"))
        
        // Cost summary table
        section.add(buildCostSummaryTable())
        
        // Per-model breakdown if available
        if let modelTable = buildModelBreakdownTable() {
            section.add(modelTable)
        }
        
        // Footer
        section.add(Divider())
        section.add(TextBlock(text: "*Cost tracking by ClaudeChain • [View workflow run](\(workflowURL))*"))
        
        return section
    }
    
    /// Build report elements for GitHub Actions workflow summary.
    ///
    /// - Returns: Section containing elements for step summary.
    public func buildWorkflowSummaryElements() -> Section {
        let section = Section()
        
        // Header
        section.add(Header(text: "✅ ClaudeChain Complete", level: 2))
        
        // PR and task info
        section.add(LabeledValue(label: "PR", value: .link(Link(text: "#\(prNumber)", url: prURL))))
        if !task.isEmpty {
            section.add(LabeledValue(label: "Task", value: .text(task)))
        }
        
        // Cost summary section
        section.add(Header(text: "💰 Cost Summary", level: 3))
        section.add(buildCostSummaryTable())
        
        // Per-model breakdown if available
        if let modelTable = buildModelBreakdownTable() {
            section.add(modelTable)
        }
        
        // Footer
        section.add(Divider())
        section.add(TextBlock(text: "*[View workflow run](\(workflowURL))*"))
        
        return section
    }
    
    // MARK: - Private Helper Methods
    
    /// Build a compact progress line for Slack notification.
    ///
    /// Example: "📊 Progress: 5/26 merged · 2 of 3 async slots in use"
    ///
    /// - Returns: Formatted progress string, or nil if no progress info.
    private func formatProgressLine() -> String? {
        guard let progressInfo = progressInfo else { return nil }
        
        let completed = progressInfo["tasks_completed"] as? Int ?? 0
        let total = progressInfo["tasks_total"] as? Int ?? 0
        let maxPRs = progressInfo["max_open_prs"] as? Int ?? 1
        // open_pr_count is before this PR was created, so add 1
        let openCount = (progressInfo["open_pr_count"] as? Int ?? 0) + 1
        
        var parts = ["📊 *Progress:* \(completed)/\(total) merged"]
        if maxPRs > 1 {
            parts.append("\(openCount) of \(maxPRs) async slots in use")
        }
        
        return parts.joined(separator: " · ")
    }
    
    /// Build the cost summary table.
    ///
    /// - Returns: Table with component costs.
    private func buildCostSummaryTable() -> Table {
        var rows: [TableRow] = [
            TableRow(cells: ["Task Completion", Formatting.formatUSD(costBreakdown.mainCost)]),
        ]
        if costBreakdown.reviewCost > 0 {
            rows.append(TableRow(cells: ["Review", Formatting.formatUSD(costBreakdown.reviewCost)]))
        }
        rows.append(contentsOf: [
            TableRow(cells: ["Summary Generation", Formatting.formatUSD(costBreakdown.summaryCost)]),
            TableRow(cells: ["**Total**", "**\(Formatting.formatUSD(costBreakdown.totalCost))**"]),
        ])
        return Table(
            columns: [
                TableColumn(header: "Component", align: .left),
                TableColumn(header: "Cost (USD)", align: .right),
            ],
            rows: rows
        )
    }
    
    /// Build the per-model breakdown section if models are available.
    ///
    /// - Returns: Section with header and table, or nil if no models.
    private func buildModelBreakdownTable() -> Section? {
        let models = costBreakdown.getAggregatedModels()
        if models.isEmpty {
            return nil
        }
        
        let section = Section()
        section.add(Header(text: "Per-Model Breakdown", level: 3))
        
        // Build rows for each model
        var rows: [TableRow] = []
        for model in models {
            let calculatedCost = (try? model.calculateCost()) ?? 0.0
            rows.append(
                TableRow(cells: [
                    model.model,
                    formatNumber(model.inputTokens),
                    formatNumber(model.outputTokens),
                    formatNumber(model.cacheReadTokens),
                    formatNumber(model.cacheWriteTokens),
                    Formatting.formatUSD(calculatedCost),
                ])
            )
        }
        
        // Add totals row
        rows.append(
            TableRow(cells: [
                "**Total**",
                "**\(formatNumber(costBreakdown.inputTokens))**",
                "**\(formatNumber(costBreakdown.outputTokens))**",
                "**\(formatNumber(costBreakdown.cacheReadTokens))**",
                "**\(formatNumber(costBreakdown.cacheWriteTokens))**",
                "**\(Formatting.formatUSD(costBreakdown.totalCost))**",
            ])
        )
        
        section.add(
            Table(
                columns: [
                    TableColumn(header: "Model", align: .left),
                    TableColumn(header: "Input", align: .right),
                    TableColumn(header: "Output", align: .right),
                    TableColumn(header: "Cache R", align: .right),
                    TableColumn(header: "Cache W", align: .right),
                    TableColumn(header: "Cost", align: .right),
                ],
                rows: rows
            )
        )
        
        return section
    }
    
    /// Format a number with thousands separators.
    ///
    /// - Parameter number: Number to format
    /// - Returns: Formatted string with commas
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}