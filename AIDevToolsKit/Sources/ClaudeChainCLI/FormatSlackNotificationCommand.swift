import ArgumentParser
import ClaudeChainService
import ClaudeChainInfrastructure
import Foundation

public struct FormatSlackNotificationCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "format-slack-notification",
        abstract: "Format Slack notification message for created PR"
    )
    
    @Option(name: .long, help: "Pull request number")
    public var prNumber: String
    
    @Option(name: .long, help: "Pull request URL")
    public var prUrl: String
    
    @Option(name: .long, help: "Name of the project")
    public var projectName: String
    
    @Option(name: .long, help: "Task description")
    public var task: String
    
    @Option(name: .long, help: "JSON string with complete cost breakdown (from CostBreakdown.toJSON())")
    public var costBreakdownJson: String
    
    @Option(name: .long, help: "Repository in format owner/repo")
    public var repo: String
    
    @Option(name: .long, help: "Optional assignee username")
    public var assignee: String = ""
    
    @Option(name: .long, help: "Number of completed tasks in spec")
    public var tasksCompleted: String = ""
    
    @Option(name: .long, help: "Total number of tasks in spec")
    public var tasksTotal: String = ""
    
    @Option(name: .long, help: "Maximum concurrent open PRs allowed")
    public var maxOpenPrs: String = ""
    
    @Option(name: .long, help: "Number of currently open PRs (before this PR)")
    public var openPrCount: String = ""
    
    public init() {}
    
    public func run() throws {
        let exitCode = try cmdFormatSlackNotification(
            prNumber: prNumber,
            prUrl: prUrl,
            projectName: projectName,
            task: task,
            costBreakdownJson: costBreakdownJson,
            repo: repo,
            assignee: assignee,
            tasksCompleted: tasksCompleted,
            tasksTotal: tasksTotal,
            maxOpenPrs: maxOpenPrs,
            openPrCount: openPrCount
        )
        
        if exitCode != 0 {
            throw ExitCode(Int32(exitCode))
        }
    }
    
    /// Format Slack notification message for a created PR.
    ///
    /// All parameters passed explicitly, no environment variable access.
    ///
    /// - Parameters:
    ///   - prNumber: Pull request number
    ///   - prUrl: Pull request URL
    ///   - projectName: Name of the project
    ///   - task: Task description
    ///   - costBreakdownJson: JSON string with complete cost breakdown (from CostBreakdown.toJSON())
    ///   - repo: Repository in format owner/repo
    ///   - assignee: Optional assignee username
    ///   - tasksCompleted: Number of completed tasks in spec
    ///   - tasksTotal: Total number of tasks in spec
    ///   - maxOpenPrs: Maximum concurrent open PRs allowed
    ///   - openPrCount: Number of currently open PRs (before this PR)
    /// - Returns: 0 on success, 1 on error
    ///
    /// Outputs (via GitHubActions):
    ///   - slack_message: Formatted Slack message in mrkdwn format
    ///   - has_pr: "true" if PR was created
    private func cmdFormatSlackNotification(
        prNumber: String,
        prUrl: String,
        projectName: String,
        task: String,
        costBreakdownJson: String,
        repo: String,
        assignee: String = "",
        tasksCompleted: String = "",
        tasksTotal: String = "",
        maxOpenPrs: String = "",
        openPrCount: String = ""
    ) throws -> Int {
        let gh = GitHubActions()
        
        // Strip whitespace from inputs
        let prNumber = prNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let prUrl = prUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = task.trimmingCharacters(in: .whitespacesAndNewlines)
        let costBreakdownJson = costBreakdownJson.trimmingCharacters(in: .whitespacesAndNewlines)
        let assignee = assignee.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If no PR, don't send notification
        if prNumber.isEmpty || prUrl.isEmpty {
            gh.writeOutput(name: "has_pr", value: "false")
            print("No PR created, skipping Slack notification")
            return 0
        }
        
        do {
            // Parse cost breakdown from structured JSON
            let costBreakdown = try CostBreakdown.fromJSON(costBreakdownJson)
            
            // Parse progress info (optional, may not be present)
            var progressInfo: [String: Any]?
            if !tasksCompleted.isEmpty && !tasksTotal.isEmpty {
                if let completed = Int(tasksCompleted), let total = Int(tasksTotal) {
                    progressInfo = [
                        "tasks_completed": completed,
                        "tasks_total": total,
                        "max_open_prs": Int(maxOpenPrs) ?? 1,
                        "open_pr_count": Int(openPrCount) ?? 0
                    ]
                }
                // If Int conversion fails, progressInfo remains nil (ignoring malformed progress data)
            }
            
            // Format the Slack message using domain model
            let message = formatPrNotification(
                prNumber: prNumber,
                prUrl: prUrl,
                projectName: projectName,
                task: task,
                costBreakdown: costBreakdown,
                repo: repo,
                assignee: assignee.isEmpty ? nil : assignee,
                progressInfo: progressInfo
            )
            
            // Output for Slack
            gh.writeOutput(name: "slack_message", value: message)
            gh.writeOutput(name: "has_pr", value: "true")
            
            print("=== Slack Notification Message ===")
            print(message)
            print()
            
            return 0
            
        } catch {
            gh.setError(message: "Error generating PR notification: \(error.localizedDescription)")
            gh.writeOutput(name: "has_pr", value: "false")
            return 1
        }
    }
    
    /// Format PR notification for Slack in mrkdwn format.
    ///
    /// - Parameters:
    ///   - prNumber: PR number
    ///   - prUrl: PR URL
    ///   - projectName: Project name
    ///   - task: Task description
    ///   - costBreakdown: CostBreakdown with costs and per-model data
    ///   - repo: Repository name (used for workflow URL generation)
    ///   - assignee: Optional assignee username
    ///   - progressInfo: Optional dict with tasks_completed, tasks_total, max_open_prs, open_pr_count
    /// - Returns: Formatted Slack message in mrkdwn
    private func formatPrNotification(
        prNumber: String,
        prUrl: String,
        projectName: String,
        task: String,
        costBreakdown: CostBreakdown,
        repo: String,
        assignee: String? = nil,
        progressInfo: [String: Any]? = nil
    ) -> String {
        // Create domain model and use its notification formatting
        // Note: run_id is not needed for Slack notification (no workflow link)
        let report = PullRequestCreatedReport(
            prNumber: prNumber,
            prURL: prUrl,
            projectName: projectName,
            task: task,
            costBreakdown: costBreakdown,
            repo: repo,
            runID: "",  // Not used for Slack notification
            assignee: assignee,
            progressInfo: progressInfo
        )
        
        return report.buildNotificationElements()
    }
}