/// Data models for ClaudeChain operations
import Foundation

// MARK: - ActionResult

/// Result of running an action script.
public struct ActionResult {
    /// Whether the script executed successfully (exit code 0 or script not found)
    public let success: Bool
    
    /// Path to the script that was executed
    public let scriptPath: String
    
    /// Standard output from the script
    public let stdout: String
    
    /// Standard error from the script
    public let stderr: String
    
    /// Exit code from the script (nil if script didn't exist)
    public let exitCode: Int?
    
    /// Whether the script file existed
    public let scriptExists: Bool
    
    public init(
        success: Bool,
        scriptPath: String,
        stdout: String = "",
        stderr: String = "",
        exitCode: Int? = nil,
        scriptExists: Bool = false
    ) {
        self.success = success
        self.scriptPath = scriptPath
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.scriptExists = scriptExists
    }
    
    /// Create result for when script doesn't exist (considered success).
    public static func scriptNotFound(scriptPath: String) -> ActionResult {
        return ActionResult(
            success: true,
            scriptPath: scriptPath,
            stdout: "",
            stderr: "",
            exitCode: nil,
            scriptExists: false
        )
    }
    
    /// Create result from script execution.
    public static func fromExecution(
        scriptPath: String,
        exitCode: Int,
        stdout: String,
        stderr: String
    ) -> ActionResult {
        return ActionResult(
            success: exitCode == 0,
            scriptPath: scriptPath,
            stdout: stdout,
            stderr: stderr,
            exitCode: exitCode,
            scriptExists: true
        )
    }
}

// MARK: - BranchInfo

/// Parsed ClaudeChain branch information.
///
/// Represents the components of a ClaudeChain branch name in the format:
/// claude-chain-{project_name}-{task_hash}
public struct BranchInfo {
    /// Name of the project (e.g., "my-refactor", "auth-migration")
    public let projectName: String
    
    /// 8-character hexadecimal task identifier (e.g., "a3f2b891")
    public let taskHash: String
    
    /// Branch format version (currently always "hash")
    public let formatVersion: String = "hash"
    
    public static let sweepCursorPrefix = "cursor at "

    public init(projectName: String, taskHash: String) {
        self.projectName = projectName
        self.taskHash = taskHash
    }
    
    /// Parse a ClaudeChain branch name into its components.
    ///
    /// Expected format: claude-chain-{project_name}-{hash}
    ///
    /// The project name can contain hyphens, so we match greedily up to the
    /// last hyphen before the hash. The hash must be exactly 8 lowercase
    /// hexadecimal characters.
    ///
    /// - Parameter branch: Branch name to parse
    /// - Returns: BranchInfo instance if branch matches pattern, nil otherwise
    public static func fromBranchName(_ branch: String) -> BranchInfo? {
        // Pattern: claude-chain-{project}-{hash}
        // Project name can contain hyphens, so we match greedily up to the last hyphen
        let pattern = #"^claude-chain-(.+)-([a-f0-9]{8})$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(branch.startIndex..<branch.endIndex, in: branch)
        
        guard let match = regex?.firstMatch(in: branch, options: [], range: range),
              let projectRange = Range(match.range(at: 1), in: branch),
              let identifierRange = Range(match.range(at: 2), in: branch) else {
            return nil
        }
        
        let projectName = String(branch[projectRange])
        let identifier = String(branch[identifierRange])
        return BranchInfo(projectName: projectName, taskHash: identifier)
    }

    /// Extract the cursor file path from sweep PR body text.
    ///
    /// Sweep PRs embed the last-processed file path in their body as "cursor at {path}".
    /// This is the authoritative source for matching a sweep PR to its cursor task — the
    /// PR title is truncated and cannot be relied upon.
    ///
    /// - Parameter text: The PR body string to search
    /// - Returns: The cursor file path, or nil if the pattern is not found
    public static func sweepCursorPath(fromText text: String) -> String? {
        guard let cursorRange = text.range(of: Self.sweepCursorPrefix) else { return nil }
        return String(text[cursorRange.upperBound...])
            .components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - TaskStatus

/// Status of a task in the spec.md file.
///
/// Used to track whether a task is pending, in progress, or completed.
public enum TaskStatus: String, CaseIterable {
    /// Task not started, no PR
    case pending = "pending"
    
    /// Task has open PR
    case inProgress = "in_progress"
    
    /// Task marked as done in spec (checkbox checked)
    case completed = "completed"
}

// MARK: - TaskWithPR

/// A task from spec.md linked to its associated PR (if any).
///
/// This model represents the relationship between a task defined in spec.md
/// and the GitHub PR that implements it. Used for detailed statistics reporting
/// to show task-level progress and identify orphaned PRs.
public struct TaskWithPR: Equatable {
    /// 8-character hash from spec task (stable identifier)
    public let taskHash: String
    
    /// Task description text from spec.md
    public let description: String
    
    /// Current task status (PENDING, IN_PROGRESS, COMPLETED)
    public let status: TaskStatus
    
    /// Associated GitHub PR if one exists, nil otherwise
    public let pr: GitHubPullRequest?
    
    public let costUSD: Double
    
    public init(
        taskHash: String,
        description: String,
        status: TaskStatus,
        pr: GitHubPullRequest? = nil,
        costUSD: Double = 0.0
    ) {
        self.taskHash = taskHash
        self.description = description
        self.status = status
        self.pr = pr
        self.costUSD = costUSD
    }
    
    /// Check if this task has an associated PR.
    ///
    /// - Returns: True if task has a PR, false otherwise
    public var hasPR: Bool {
        return pr != nil
    }
    
    /// Get the PR number if available.
    ///
    /// - Returns: PR number or nil if no PR
    public var prNumber: Int? {
        return pr?.number
    }
    
    /// Get the PR state if available.
    ///
    /// - Returns: PRState enum value or nil if no PR
    /// - Throws: ConfigurationError if PR state is invalid
    public var prState: PRState? {
        guard let pr = pr else { return nil }
        return try? PRState.fromString(pr.state)
    }
}

// MARK: - Helper Functions

/// Parse ISO 8601 timestamp, ensuring timezone-aware result
///
/// Handles both legacy format (naive) and new format (timezone-aware):
/// - "2025-12-29T23:47:49.299060" → parsed with UTC timezone added
/// - "2025-12-29T23:47:49.299060+00:00" → parsed as-is
/// - "2025-12-29T23:47:49.299060Z" → parsed as-is
///
/// - Parameter timestampStr: ISO 8601 formatted timestamp string
/// - Returns: Timezone-aware Date object (always has timezone info)
public func parseISOTimestamp(_ timestampStr: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    
    let cleanedString = timestampStr.replacingOccurrences(of: "Z", with: "+00:00")
    
    if let date = formatter.date(from: cleanedString) {
        return date
    }
    
    // Try without fractional seconds
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: cleanedString) {
        return date
    }
    
    // Fallback: parse as legacy format and add UTC timezone
    let legacyFormatter = DateFormatter()
    legacyFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
    legacyFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    
    return legacyFormatter.date(from: timestampStr) ?? Date()
}

// MARK: - CapacityResult

/// Result of project capacity check.
///
/// Capacity is determined by the project's maxOpenPRs setting (default: 1).
public struct CapacityResult {
    public let hasCapacity: Bool
    public let openPRs: [[String: Any]]
    public let projectName: String
    public let maxOpenPRs: Int
    public let assignees: [String]
    public let reviewers: [String]
    
    public init(
        hasCapacity: Bool,
        openPRs: [[String: Any]],
        projectName: String,
        maxOpenPRs: Int = 1,
        assignees: [String] = [],
        reviewers: [String] = []
    ) {
        self.hasCapacity = hasCapacity
        self.openPRs = openPRs
        self.projectName = projectName
        self.maxOpenPRs = maxOpenPRs
        self.assignees = assignees
        self.reviewers = reviewers
    }
    
    /// Number of currently open PRs
    public var openCount: Int {
        return openPRs.count
    }
    
    /// Generate formatted summary for GitHub Actions output
    public func formatSummary() -> String {
        var lines: [String] = ["## Capacity Check", ""]
        
        // Project header with status emoji
        let statusEmoji = hasCapacity ? "✅" : "❌"
        lines.append("### \(statusEmoji) **\(projectName)**")
        lines.append("")
        
        // Capacity info
        lines.append("**Max PRs Allowed:** \(maxOpenPRs)")
        lines.append("**Currently Open:** \(openCount)/\(maxOpenPRs)")
        lines.append("")
        
        // List open PRs with details
        if !openPRs.isEmpty {
            lines.append("**Open PRs:**")
            for prInfo in openPRs {
                let prNum = prInfo["pr_number"] as? Int ?? 0
                let taskDesc = prInfo["task_description"] as? String ?? "Unknown task"
                lines.append("- PR #\(prNum): \(taskDesc)")
            }
            lines.append("")
        } else {
            lines.append("**Open PRs:** None")
            lines.append("")
        }
        
        // Final decision
        lines.append("---")
        lines.append("")
        if !hasCapacity {
            lines.append("**Decision:** ⏸️ At capacity - waiting for PR to be reviewed")
        } else {
            if !assignees.isEmpty {
                lines.append("**Decision:** ✅ Capacity available - assignees: **\(assignees.joined(separator: ", "))**")
            } else {
                lines.append("**Decision:** ✅ Capacity available - PR will be created without assignee")
            }
            if !reviewers.isEmpty {
                lines.append("**Reviewers:** \(reviewers.joined(separator: ", "))")
            }
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - PRReference

/// Reference to a pull request for statistics
///
/// Lightweight model that stores just the information needed for
/// statistics display, not the full PR details.
public struct PRReference {
    public let prNumber: Int
    public let title: String
    public let project: String
    /// merged_at or created_at depending on context
    public let timestamp: Date
    
    public init(prNumber: Int, title: String, project: String, timestamp: Date) {
        self.prNumber = prNumber
        self.title = title
        self.project = project
        self.timestamp = timestamp
    }
    
    /// Format for display: '[project] #123: Title'
    public func formatDisplay() -> String {
        return "[\(project)] #\(prNumber): \(title)"
    }
}

// MARK: - TeamMemberStats

/// Statistics for a single team member
public class TeamMemberStats {
    public let username: String
    /// Type-safe list of PR references
    public var mergedPRs: [PRReference] = []
    /// Type-safe list of PR references
    public var openPRs: [PRReference] = []
    
    public init(username: String) {
        self.username = username
    }
    
    /// Number of merged PRs
    public var mergedCount: Int {
        return mergedPRs.count
    }
    
    /// Number of open PRs
    public var openCount: Int {
        return openPRs.count
    }
    
    /// Total number of PRs (merged + open)
    public var totalCount: Int {
        return mergedCount + openCount
    }
    
    /// Add a merged PR to this member's stats
    public func addMergedPR(_ pr: PRReference) {
        mergedPRs.append(pr)
    }
    
    /// Add an open PR to this member's stats
    public func addOpenPR(_ pr: PRReference) {
        openPRs.append(pr)
    }
}

// MARK: - ProjectStats

/// Statistics for a single project
public class ProjectStats {
    /// Name of the project
    public let projectName: String
    
    /// Path to the spec.md file
    public let specPath: String
    
    /// Total number of tasks in spec.md
    public var totalTasks: Int = 0
    
    /// Number of completed tasks (checked off)
    public var completedTasks: Int = 0
    
    /// Number of tasks with open PRs
    public var inProgressTasks: Int = 0
    
    /// Number of tasks without PRs
    public var pendingTasks: Int = 0
    
    /// Total AI cost for this project
    public var totalCostUSD: Double = 0.0
    
    /// List of open PRs for this project
    public var openPRs: [GitHubPullRequest] = []
    
    /// Number of PRs that are stale
    public var stalePRCount: Int = 0
    
    /// Detailed list of tasks with their PR associations
    public var tasks: [TaskWithPR] = []
    
    /// PRs whose task hashes don't match any current spec task
    public var orphanedPRs: [GitHubPullRequest] = []
    
    public init(projectName: String, specPath: String) {
        self.projectName = projectName
        self.specPath = specPath
    }
    
    /// Calculate completion percentage
    public var completionPercentage: Double {
        guard totalTasks > 0 else { return 0.0 }
        return (Double(completedTasks) / Double(totalTasks)) * 100
    }
    
    /// Check if project has remaining tasks but no open PRs.
    ///
    /// This indicates a project that may need attention - there's work
    /// to be done but no PRs in progress.
    ///
    /// - Returns: True if pendingTasks > 0 and inProgressTasks == 0
    public var hasRemainingTasks: Bool {
        return pendingTasks > 0 && inProgressTasks == 0
    }
    
    /// Generate Unicode progress bar
    ///
    /// - Parameter width: Number of characters for the bar
    /// - Returns: String like "████████░░ 80%"
    public func formatProgressBar(width: Int = 10) -> String {
        guard totalTasks > 0 else {
            return String(repeating: "░", count: width) + " 0%"
        }
        
        let pct = completionPercentage
        var filled = Int((pct / 100) * Double(width))
        
        // Show at least 1 filled block if there's any progress
        if pct > 0 && filled == 0 {
            filled = 1
        }
        
        let empty = width - filled
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
        return String(format: "%@ %.0f%%", bar, pct)
    }
    
    /// Build summary section for this project.
    ///
    /// - Returns: Section containing project summary with progress bar
    public func toSummarySection() -> Section {
        let section = Section(header: Header(text: "📊 \(projectName)", level: 3))
        
        // Progress bar and completion info
        section.add(TextBlock(text: "\(formatProgressBar()) · \(completedTasks)/\(totalTasks) complete"))
        
        // Compact status breakdown - only show non-zero counts
        var statusParts = ["✅\(completedTasks)"]
        if inProgressTasks > 0 {
            statusParts.append("🔄\(inProgressTasks)")
        }
        if pendingTasks > 0 {
            statusParts.append("⏸️\(pendingTasks)")
        }
        if totalCostUSD > 0 {
            statusParts.append("💰\(Formatting.formatUSD(totalCostUSD))")
        }
        
        section.add(TextBlock(text: statusParts.joined(separator: " · ")))
        return section
    }
}

// MARK: - StatisticsReport

/// Aggregated statistics report for all projects and team members
public class StatisticsReport {
    /// username -> TeamMemberStats
    public var teamStats: [String: TeamMemberStats] = [:]
    
    /// project_name -> ProjectStats
    public var projectStats: [String: ProjectStats] = [:]
    
    public var generatedAt: Date?
    
    /// GitHub repository (owner/name)
    public var repo: String?
    
    /// Time to generate report
    public var generationTimeSeconds: Double?
    
    public init(repo: String? = nil) {
        self.repo = repo
    }
    
    /// Add team member statistics
    public func addTeamMember(_ stats: TeamMemberStats) {
        teamStats[stats.username] = stats
    }
    
    /// Add project statistics
    public func addProject(_ stats: ProjectStats) {
        projectStats[stats.projectName] = stats
    }
    
    /// Get projects that need attention.
    ///
    /// A project needs attention if:
    /// - It has stale PRs (stalePRCount > 0), OR
    /// - It has remaining tasks but no open PRs (hasRemainingTasks is true), OR
    /// - It has open orphaned PRs (PRs whose tasks were removed from spec)
    ///
    /// Note: Merged orphaned PRs don't require attention (shown in workflow report only).
    ///
    /// - Returns: List of ProjectStats for projects needing attention, sorted by project name
    public func projectsNeedingAttention() -> [ProjectStats] {
        let needingAttention = projectStats.values.filter { stats in
            let hasOpenOrphanedPRs = stats.orphanedPRs.contains { $0.isOpen() }
            return stats.stalePRCount > 0 || stats.hasRemainingTasks || hasOpenOrphanedPRs
        }
        return needingAttention.sorted { $0.projectName < $1.projectName }
    }
    
    /// Build PR URL from repo and PR number
    private func buildPRURL(prNumber: Int) -> String? {
        guard let repo = repo else { return nil }
        return "https://github.com/\(repo)/pull/\(prNumber)"
    }
    
    /// Format how long a PR was/is open with appropriate units
    private func formatPRDuration(_ pr: GitHubPullRequest) -> String {
        let endTime: Date
        if pr.state == "open" {
            endTime = Date()
        } else {
            endTime = pr.mergedAt ?? Date()
        }
        
        let delta = endTime.timeIntervalSince(pr.createdAt)
        let totalMinutes = Int(delta / 60)
        let days = Int(delta / 86400)
        
        if days >= 1 {
            return "\(days)d"
        } else if totalMinutes >= 60 {
            return "\(totalMinutes / 60)h"
        } else {
            return "\(max(1, totalMinutes))m"
        }
    }
    
    /// Build header section with metadata
    public func toHeaderSection() -> Section {
        let section = Section()
        
        if let repo = repo {
            section.add(TextBlock(text: repo, style: .italic))
        }
        
        return section
    }
    
    /// Build leaderboard section showing top contributors
    public func toLeaderboardSection() -> Section {
        let section = Section(header: Header(text: "🏆 Leaderboard", level: 2))
        
        guard !teamStats.isEmpty else { return section }
        
        // Sort by activity level (merged PRs desc, then username)
        let sortedMembers = teamStats.sorted { first, second in
            if first.value.mergedCount != second.value.mergedCount {
                return first.value.mergedCount > second.value.mergedCount
            }
            return first.key < second.key
        }
        
        // Filter to only members with activity
        let activeMembers = sortedMembers.filter { $0.value.mergedCount > 0 }
        
        guard !activeMembers.isEmpty else { return section }
        
        // Build table
        let columns = [
            TableColumn(header: "Rank", align: .left),
            TableColumn(header: "Username", align: .left),
            TableColumn(header: "Open", align: .right),
            TableColumn(header: "Merged", align: .right),
        ]
        
        let medals = ["🥇", "🥈", "🥉"]
        var rows: [TableRow] = []
        for (idx, member) in activeMembers.enumerated() {
            let rankDisplay = idx < 3 ? medals[idx] : "#\(idx+1)"
            let username = String(member.key.prefix(15))
            rows.append(TableRow(cells: [
                rankDisplay,
                username,
                String(member.value.openCount),
                String(member.value.mergedCount),
            ]))
        }
        
        section.add(Table(columns: columns, rows: rows, inCodeBlock: true))
        return section
    }
    
    /// Build project progress section with statistics table
    public func toProjectProgressSection() -> Section {
        let section = Section(header: Header(text: "Project Progress", level: 2))
        
        guard !projectStats.isEmpty else {
            section.add(TextBlock(text: "No projects found", style: .italic))
            return section
        }
        
        // Build table
        let columns = [
            TableColumn(header: "Project", align: .left),
            TableColumn(header: "Open", align: .right),
            TableColumn(header: "Merged", align: .right),
            TableColumn(header: "Total", align: .right),
            TableColumn(header: "Progress", align: .left),
            TableColumn(header: "Cost", align: .right),
        ]
        
        var rows: [TableRow] = []
        for projectName in projectStats.keys.sorted() {
            let stats = projectStats[projectName]!
            
            // Create progress bar
            let progressBar = stats.formatProgressBar()
            
            // Format cost
            let costDisplay = stats.totalCostUSD > 0 ? Formatting.formatUSD(stats.totalCostUSD) : "-"
            
            rows.append(TableRow(cells: [
                String(projectName.prefix(20)),
                String(stats.inProgressTasks),
                String(stats.completedTasks),
                String(stats.totalTasks),
                progressBar,
                costDisplay,
            ]))
        }
        
        section.add(Table(columns: columns, rows: rows, inCodeBlock: true))
        return section
    }
    
    /// Build warnings section for projects needing attention
    public func toWarningsSection(stalePRDays: Int = 7) -> Section {
        let section = Section(header: Header(text: "⚠️ Needs Attention", level: 2))
        
        let projects = projectsNeedingAttention()
        guard !projects.isEmpty else { return section }
        
        for stats in projects {
            var projectItems: [ListItem] = []
            
            // Collect all open PRs with their status indicators
            for pr in stats.openPRs {
                var indicators: [String] = []
                if pr.isStale(stalePRDays: stalePRDays) {
                    indicators.append("stale")
                }
                let assignee = pr.firstAssignee ?? "unassigned"
                
                var statusParts = [formatPRDuration(pr), assignee]
                statusParts.append(contentsOf: indicators)
                let statusText = statusParts.joined(separator: ", ")
                
                if let url = pr.url ?? buildPRURL(prNumber: pr.number) {
                    projectItems.append(ListItem(content: .link(Link(text: "#\(pr.number) (\(statusText))", url: url)), bullet: "•"))
                } else {
                    projectItems.append(ListItem(content: .text("#\(pr.number) (\(statusText))"), bullet: "•"))
                }
            }
            
            // Add open orphaned PRs
            for pr in stats.orphanedPRs {
                if pr.isOpen() {
                    let statusText = "\(formatPRDuration(pr)), orphaned"
                    if let url = pr.url ?? buildPRURL(prNumber: pr.number) {
                        projectItems.append(ListItem(content: .link(Link(text: "#\(pr.number) (\(statusText))", url: url)), bullet: "•"))
                    } else {
                        projectItems.append(ListItem(content: .text("#\(pr.number) (\(statusText))"), bullet: "•"))
                    }
                }
            }
            
            // Add warning if no open PRs but tasks remain
            if stats.hasRemainingTasks {
                projectItems.append(ListItem(content: .text("No open PRs (\(stats.pendingTasks) tasks remaining)"), bullet: "•"))
            }
            
            if !projectItems.isEmpty {
                section.add(TextBlock(text: stats.projectName, style: .bold))
                section.add(ListBlock(items: projectItems))
            }
        }
        
        return section
    }
    
    /// Format for Slack with complete report structure
    public func formatForSlack(
        showAssigneeStats: Bool = false,
        stalePRDays: Int = 7
    ) -> String {
        let formatter = SlackReportFormatter()
        var sections: [String] = []
        
        // Header section
        let header = toHeaderSection()
        if !header.isEmpty() {
            sections.append(formatter.formatSection(header))
        }
        
        // Leaderboard section (only if enabled)
        if showAssigneeStats {
            let leaderboard = toLeaderboardSection()
            if !leaderboard.isEmpty() {
                sections.append(formatter.formatSection(leaderboard))
            }
        }
        
        // Project progress section
        sections.append(formatter.formatSection(toProjectProgressSection()))
        
        // Warnings section
        let warnings = toWarningsSection(stalePRDays: stalePRDays)
        if !warnings.isEmpty() {
            sections.append(formatter.formatSection(warnings))
        }
        
        // Generation time footer
        if let generationTimeSeconds = generationTimeSeconds {
            sections.append("_Elapsed time: \(String(format: "%.1f", generationTimeSeconds))s_")
        }
        
        return sections.joined(separator: "\n\n")
    }
    
    /// Generate Block Kit JSON structure for Slack webhook
    ///
    /// - Parameters:
    ///   - showAssigneeStats: Whether to include assignee leaderboard
    ///   - runUrl: GitHub Actions run URL for footer
    ///   - hideCompletedProjects: Whether to exclude completed projects
    /// - Returns: Slack Block Kit payload dictionary
    public func formatForSlackBlocks(
        showAssigneeStats: Bool = false,
        runUrl: String? = nil,
        hideCompletedProjects: Bool = false
    ) -> [String: Any] {
        let formatter = SlackBlockKitFormatter(repo: repo ?? "")
        var blocks: [[String: Any]] = []
        
        // Chains section header (matches leaderboard style)
        blocks.append(contentsOf: formatter.formatHeaderBlocks())
        
        // Project progress blocks (skip fully completed projects)
        for projectName in projectStats.keys.sorted() {
            if let stats = projectStats[projectName] {
                // Optionally skip completed projects (all tasks merged, no open PRs)
                if hideCompletedProjects {
                    let isCompleted = (
                        stats.completedTasks == stats.totalTasks &&
                        stats.totalTasks > 0 &&
                        stats.openPRs.isEmpty
                    )
                    if isCompleted {
                        continue
                    }
                }
                
                // Build open PRs list with age
                var openPRs: [[String: Any]] = []
                for pr in stats.openPRs {
                    openPRs.append([
                        "number": pr.number,
                        "title": pr.taskDescription,
                        "url": pr.url ?? buildPRURL(prNumber: pr.number) ?? "",
                        "age_days": pr.daysOpen,
                        "age_formatted": formatPRDuration(pr)
                    ])
                }
                
                blocks.append(contentsOf: formatter.formatProjectBlocks(
                    projectName: projectName,
                    merged: stats.completedTasks,
                    total: stats.totalTasks,
                    costUSD: stats.totalCostUSD,
                    openPRs: openPRs.isEmpty ? nil : openPRs
                ))
            }
        }
        
        // Leaderboard blocks (only if enabled) - after project progress
        if showAssigneeStats {
            let sortedMembers = teamStats.sorted { first, second in
                if first.value.mergedCount != second.value.mergedCount {
                    return first.value.mergedCount > second.value.mergedCount
                }
                return first.key < second.key
            }
            let activeMembers = sortedMembers.compactMap { (username, stats) -> [String: Any]? in
                guard stats.mergedCount > 0 else { return nil }
                return ["username": username, "merged": stats.mergedCount]
            }
            blocks.append(contentsOf: formatter.formatLeaderboardBlocks(entries: activeMembers))
        }
        
        // Footer with link to GitHub Actions run (and elapsed time if available)
        if let runUrl = runUrl {
            let footerText = formatFooterText(runURL: runUrl, elapsedSeconds: generationTimeSeconds)
            blocks.append(contextBlock(footerText))
        }
        
        // Truncate to Slack's 50-block limit
        let maxBlocks = 50
        if blocks.count > maxBlocks {
            let originalCount = blocks.count
            let truncatedCount = originalCount - (maxBlocks - 1)
            print("WARNING: Slack block count (\(originalCount)) exceeds \(maxBlocks)-block limit. \(truncatedCount) blocks truncated.")
            blocks = Array(blocks.prefix(maxBlocks - 1))
            blocks.append(contextBlock("⚠️ \(truncatedCount) blocks truncated due to Slack limit"))
        }
        
        return formatter.buildMessage(blocks: blocks, fallbackText: "ClaudeChain Stats")
    }
    
    /// Format leaderboard showing top contributors with rankings
    ///
    /// - Parameter forSlack: If true, use Slack mrkdwn format; otherwise GitHub markdown
    /// - Returns: Formatted leaderboard string
    public func formatLeaderboard(forSlack: Bool = false) -> String {
        let section = toLeaderboardSection()
        if section.isEmpty() {
            return ""
        }
        
        let formatter: ReportFormatter = forSlack ? SlackReportFormatter() : MarkdownReportFormatter()
        return formatter.formatSection(section)
    }
    
    /// Format warnings section for projects needing attention
    ///
    /// - Parameters:
    ///   - forSlack: If true, use Slack mrkdwn format; otherwise GitHub markdown
    ///   - stalePRDays: Threshold for stale PRs
    /// - Returns: Formatted warnings section string
    public func formatWarningsSection(forSlack: Bool = false, stalePRDays: Int = 7) -> String {
        let section = toWarningsSection(stalePRDays: stalePRDays)
        if section.isEmpty() {
            return ""
        }
        
        let formatter: ReportFormatter = forSlack ? SlackReportFormatter() : MarkdownReportFormatter()
        return formatter.formatSection(section)
    }
    
    /// Format detailed task view showing each task with its PR association
    ///
    /// - Parameter forSlack: If true, use Slack mrkdwn format; otherwise GitHub markdown
    /// - Returns: Formatted project details string
    public func formatProjectDetails(forSlack: Bool = false) -> String {
        let section = toProjectDetailsSection()
        let formatter: ReportFormatter = forSlack ? SlackReportFormatter() : MarkdownReportFormatter()
        return formatter.formatSection(section)
    }
    
    /// Export as JSON for programmatic access
    ///
    /// - Returns: JSON string representation of the report
    public func toJSON() -> String {
        var data: [String: Any] = [:]
        
        // Add metadata
        if let generatedAt = generatedAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            data["generated_at"] = formatter.string(from: generatedAt)
        } else {
            data["generated_at"] = nil
        }
        data["repo"] = repo
        
        // Serialize project stats
        var projects: [String: Any] = [:]
        for (projectName, stats) in projectStats {
            projects[projectName] = [
                "total_tasks": stats.totalTasks,
                "completed_tasks": stats.completedTasks,
                "in_progress_tasks": stats.inProgressTasks,
                "pending_tasks": stats.pendingTasks,
                "completion_percentage": stats.completionPercentage
            ]
        }
        data["projects"] = projects
        
        // Serialize team member stats
        var teamMembers: [String: Any] = [:]
        for (username, stats) in teamStats {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            teamMembers[username] = [
                "merged_prs": stats.mergedPRs.map { pr in
                    [
                        "pr_number": pr.prNumber,
                        "title": pr.title,
                        "project": pr.project,
                        "timestamp": formatter.string(from: pr.timestamp)
                    ]
                },
                "open_prs": stats.openPRs.map { pr in
                    [
                        "pr_number": pr.prNumber,
                        "title": pr.title,
                        "project": pr.project,
                        "timestamp": formatter.string(from: pr.timestamp)
                    ]
                },
                "merged_count": stats.mergedCount,
                "open_count": stats.openCount
            ]
        }
        data["team_members"] = teamMembers
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted])
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            print("Error serializing statistics to JSON: \(error)")
            return "{}"
        }
    }
    
    /// Build detailed task view showing each task with its PR association
    ///
    /// - Returns: Section containing detailed task-PR mappings for all projects
    private func toProjectDetailsSection() -> Section {
        let section = Section()
        
        for projectName in projectStats.keys.sorted() {
            if let stats = projectStats[projectName] {
                // Project header with completion count
                let headerText = "\(projectName) (\(stats.completedTasks)/\(stats.totalTasks) complete)"
                let projectSection = Section(header: Header(text: headerText, level: 2))
                
                // Tasks section as a table
                if !stats.tasks.isEmpty {
                    projectSection.add(Header(text: "Tasks", level: 3))
                    
                    // Build table with columns: Checkbox, Task, PR, Status, Cost
                    let columns = [
                        TableColumn(header: "", align: .center),  // checkbox
                        TableColumn(header: "Task", align: .left),
                        TableColumn(header: "PR", align: .left),
                        TableColumn(header: "Status", align: .left),
                        TableColumn(header: "Cost", align: .right)
                    ]
                    
                    var rows: [TableRow] = []
                    var totalCost = 0.0
                    for task in stats.tasks {
                        let checkbox = task.status == .completed ? "✓" : ""
                        // Truncate long descriptions
                        let desc = task.description.count > 50 ? 
                            String(task.description.prefix(50)) + "..." : 
                            task.description
                        
                        let prInfoStr: String
                        let status: String
                        if task.hasPR, let pr = task.pr {
                            let duration = formatPRDuration(pr)
                            if pr.isMerged() {
                                status = "Merged (\(duration))"
                            } else if pr.isOpen() {
                                status = "Open (\(duration))"
                            } else {
                                status = "Closed"
                            }
                            // For table cells, we need strings, not Link objects
                            if let url = pr.url ?? buildPRURL(prNumber: pr.number) {
                                prInfoStr = "[#\(pr.number)](\(url))"  // Markdown link format
                            } else {
                                prInfoStr = "#\(pr.number)"
                            }
                        } else {
                            prInfoStr = "-"
                            status = "-"
                        }
                        
                        let costStr = task.costUSD > 0 ? String(format: "$%.2f", task.costUSD) : "-"
                        totalCost += task.costUSD
                        
                        rows.append(TableRow(cells: [checkbox, desc, prInfoStr, status, costStr]))
                    }
                    
                    // Add total row if there are costs
                    if totalCost > 0 {
                        rows.append(TableRow(cells: ["", "", "", "**Total**", String(format: "**$%.2f**", totalCost)]))
                    }
                    
                    projectSection.add(Table(columns: columns, rows: rows))
                }
                
                // Orphaned PRs section
                if !stats.orphanedPRs.isEmpty {
                    var orphanItems: [ListItem] = []
                    for pr in stats.orphanedPRs {
                        let duration = formatPRDuration(pr)
                        let state: String
                        if pr.isMerged() {
                            state = "Merged, \(duration)"
                        } else if pr.isOpen() {
                            state = "Open, \(duration)"
                        } else {
                            state = "Closed"
                        }
                        orphanItems.append(ListItem(content: .text("PR #\(pr.number) (\(state)) - Task removed from spec"), bullet: "•"))
                    }
                    
                    projectSection.add(Header(text: "Orphaned PRs", level: 3))
                    projectSection.add(TextBlock(
                        text: "> **Note:** Orphaned PRs are pull requests whose associated tasks have been " +
                              "removed from the spec file.\n" +
                              "> These may need manual review to determine if they should be closed or " +
                              "if the task should be restored."
                    ))
                    projectSection.add(ListBlock(items: orphanItems))
                }
                
                section.add(projectSection)
            }
        }
        
        return section
    }
}

// MARK: - TeamMemberStats Extensions

extension TeamMemberStats {
    /// Format summary for this team member
    ///
    /// - Returns: Formatted summary string
    public func formatSummary() -> String {
        var lines: [String] = []
        lines.append("### **\(username)**")
        lines.append("")
        lines.append("**Activity:** \(mergedCount) merged, \(openCount) open")
        
        if !mergedPRs.isEmpty {
            lines.append("")
            lines.append("**Merged PRs:**")
            for pr in mergedPRs.sorted(by: { $0.timestamp > $1.timestamp }) {
                lines.append("- \(pr.formatDisplay())")
            }
        }
        
        if !openPRs.isEmpty {
            lines.append("")
            lines.append("**Open PRs:**")
            for pr in openPRs.sorted(by: { $0.timestamp > $1.timestamp }) {
                lines.append("- \(pr.formatDisplay())")
            }
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - AITask

/// Metadata for a single AI operation within a PR
///
/// Represents one AI task (e.g., code generation, PR summary, refinement)
/// that contributes to a pull request.
public struct AITask {
    /// Task type: "PRCreation", "PRRefinement", "PRSummary", etc.
    public let type: String
    
    /// AI model used (e.g., "claude-sonnet-4", "claude-opus-4")
    public let model: String
    
    /// Cost for this specific AI operation
    public let costUSD: Double
    
    /// When this AI task was executed
    public let createdAt: Date
    
    /// Input tokens used
    public let tokensInput: Int
    
    /// Output tokens generated
    public let tokensOutput: Int
    
    /// Time taken for this operation
    public let durationSeconds: Double
    
    public init(
        type: String,
        model: String,
        costUSD: Double,
        createdAt: Date,
        tokensInput: Int = 0,
        tokensOutput: Int = 0,
        durationSeconds: Double = 0.0
    ) {
        self.type = type
        self.model = model
        self.costUSD = costUSD
        self.createdAt = createdAt
        self.tokensInput = tokensInput
        self.tokensOutput = tokensOutput
        self.durationSeconds = durationSeconds
    }
    
    /// Parse from JSON dictionary
    public static func fromDict(_ data: [String: Any]) -> AITask? {
        guard let type = data["type"] as? String,
              let model = data["model"] as? String,
              let costUSD = data["cost_usd"] as? Double,
              let createdAtString = data["created_at"] as? String else {
            return nil
        }
        
        let createdAt = parseISOTimestamp(createdAtString)
        let tokensInput = data["tokens_input"] as? Int ?? 0
        let tokensOutput = data["tokens_output"] as? Int ?? 0
        let durationSeconds = data["duration_seconds"] as? Double ?? 0.0
        
        return AITask(
            type: type,
            model: model,
            costUSD: costUSD,
            createdAt: createdAt,
            tokensInput: tokensInput,
            tokensOutput: tokensOutput,
            durationSeconds: durationSeconds
        )
    }
    
    /// Serialize to JSON dictionary
    public func toDict() -> [String: Any] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return [
            "type": type,
            "model": model,
            "cost_usd": costUSD,
            "created_at": dateFormatter.string(from: createdAt),
            "tokens_input": tokensInput,
            "tokens_output": tokensOutput,
            "duration_seconds": durationSeconds,
        ]
    }
}

// MARK: - TaskMetadata

/// Metadata about completed tasks for reporting and cost tracking.
public struct TaskMetadata {
    /// Task description
    public let taskDescription: String
    
    /// Task hash for unique identification
    public let taskHash: String
    
    /// When the task was completed
    public let completedAt: Date
    
    /// Total cost for this task execution
    public let costUSD: Double
    
    /// Pull request number created for this task
    public let prNumber: Int
    
    /// Assignee for this task (GitHub username)
    public let assignee: String
    
    /// Model usage breakdown (model name -> usage data)
    public let modelUsage: [String: [String: Any]]
    
    public init(
        taskDescription: String,
        taskHash: String,
        completedAt: Date,
        costUSD: Double,
        prNumber: Int,
        assignee: String,
        modelUsage: [String: [String: Any]] = [:]
    ) {
        self.taskDescription = taskDescription
        self.taskHash = taskHash
        self.completedAt = completedAt
        self.costUSD = costUSD
        self.prNumber = prNumber
        self.assignee = assignee
        self.modelUsage = modelUsage
    }
    
    /// Convert to dictionary for JSON serialization
    public func toDict() -> [String: Any] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return [
            "task_description": taskDescription,
            "task_hash": taskHash,
            "completed_at": dateFormatter.string(from: completedAt),
            "cost_usd": costUSD,
            "pr_number": prNumber,
            "assignee": assignee,
            "model_usage": modelUsage
        ]
    }
    
    /// Create from dictionary (for JSON deserialization)
    public static func fromDict(_ dict: [String: Any]) -> TaskMetadata? {
        guard let taskDescription = dict["task_description"] as? String,
              let taskHash = dict["task_hash"] as? String,
              let completedAtString = dict["completed_at"] as? String,
              let costUSD = dict["cost_usd"] as? Double,
              let prNumber = dict["pr_number"] as? Int,
              let assignee = dict["assignee"] as? String else {
            return nil
        }
        
        let completedAt = parseISOTimestamp(completedAtString)
        let modelUsage = dict["model_usage"] as? [String: [String: Any]] ?? [:]
        
        return TaskMetadata(
            taskDescription: taskDescription,
            taskHash: taskHash,
            completedAt: completedAt,
            costUSD: costUSD,
            prNumber: prNumber,
            assignee: assignee,
            modelUsage: modelUsage
        )
    }
}

// MARK: - ProjectMetadata

/// Metadata for a complete project, tracking all completed tasks.
public struct ProjectMetadata {
    /// Project name
    public let projectName: String
    
    /// Project creation timestamp
    public let createdAt: Date
    
    /// Last update timestamp
    public var updatedAt: Date
    
    /// Total cost for all tasks in this project
    public var totalCostUSD: Double
    
    /// List of completed task metadata
    public var completedTasks: [TaskMetadata]
    
    public init(
        projectName: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        totalCostUSD: Double = 0.0,
        completedTasks: [TaskMetadata] = []
    ) {
        self.projectName = projectName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.totalCostUSD = totalCostUSD
        self.completedTasks = completedTasks
    }
    
    /// Add a completed task and update totals
    public mutating func addCompletedTask(_ task: TaskMetadata) {
        completedTasks.append(task)
        totalCostUSD += task.costUSD
        updatedAt = Date()
    }
    
    /// Convert to dictionary for JSON serialization
    public func toDict() -> [String: Any] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return [
            "project_name": projectName,
            "created_at": dateFormatter.string(from: createdAt),
            "updated_at": dateFormatter.string(from: updatedAt),
            "total_cost_usd": totalCostUSD,
            "completed_tasks": completedTasks.map { $0.toDict() }
        ]
    }
    
    /// Create from dictionary (for JSON deserialization)
    public static func fromDict(_ dict: [String: Any]) -> ProjectMetadata? {
        guard let projectName = dict["project_name"] as? String,
              let createdAtString = dict["created_at"] as? String,
              let updatedAtString = dict["updated_at"] as? String,
              let totalCostUSD = dict["total_cost_usd"] as? Double else {
            return nil
        }
        
        let createdAt = parseISOTimestamp(createdAtString)
        let updatedAt = parseISOTimestamp(updatedAtString)
        
        let completedTasks: [TaskMetadata]
        if let tasksData = dict["completed_tasks"] as? [[String: Any]] {
            completedTasks = tasksData.compactMap { TaskMetadata.fromDict($0) }
        } else {
            completedTasks = []
        }
        
        return ProjectMetadata(
            projectName: projectName,
            createdAt: createdAt,
            updatedAt: updatedAt,
            totalCostUSD: totalCostUSD,
            completedTasks: completedTasks
        )
    }
}