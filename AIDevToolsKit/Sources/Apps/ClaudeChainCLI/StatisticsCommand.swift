import ArgumentParser
import ClaudeChainService
import ClaudeChainSDK
import ClaudeChainFeature
import Foundation

public struct StatisticsCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "statistics",
        abstract: "Generate statistics and reports"
    )
    
    @Option(name: .long, help: "GitHub repository (owner/name)")
    public var repo: String?
    
    @Option(name: .long, help: "Name of the workflow that creates PRs (for artifact discovery)")
    public var workflowFile: String?
    
    @Option(name: .long, help: "Base branch to fetch specs from (default: main)")
    public var baseBranch: String?
    
    @Option(name: .long, help: "Path to configuration file")
    public var configPath: String?
    
    @Option(name: .long, help: "Days to look back for statistics (default: 30)")
    public var daysBack: Int?
    
    @Option(name: .long, help: "Output format (default: slack)")
    public var format: String?
    
    @Option(name: .long, help: "Slack webhook URL for posting statistics")
    public var slackWebhookUrl: String?
    
    @Flag(name: .long, help: "Show assignee leaderboard statistics (default: hidden)")
    public var showAssigneeStats: Bool = false
    
    @Flag(name: .long, help: "Hide fully completed projects from Slack output (default: shown)")
    public var hideCompleted: Bool = false
    
    @Option(name: .long, help: "GitHub Actions run URL for 'See details' footer")
    public var runUrl: String?
    
    public init() {}
    
    public func run() throws {
        print("=== ClaudeChain Statistics Collection ===")
        
        let gh = GitHubActions()
        
        // Get values from environment variables or command line arguments
        let repoName = repo ?? ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"] ?? ""
        let workflowFileName = workflowFile ?? ""
        let baseBranchName = baseBranch ?? "main"
        let daysBackValue = daysBack ?? Constants.defaultStatsDaysBack
        let formatType = format ?? "slack"
        let slackWebhookUrlValue = slackWebhookUrl ?? ""
        let runUrlValue = runUrl ?? ""
        
        print("Days back: \(daysBackValue)")
        
        guard !repoName.isEmpty else {
            gh.setError(message: "GitHub repository not specified. Set GITHUB_REPOSITORY environment variable or use --repo option.")
            gh.writeOutput(name: "has_statistics", value: "false")
            throw ExitCode.failure
        }
        
        guard !workflowFileName.isEmpty else {
            gh.setError(message: "Workflow file not specified. Use --workflow-file option.")
            gh.writeOutput(name: "has_statistics", value: "false")
            throw ExitCode.failure
        }
        
        do {
            // Initialize services (dependency injection pattern)
            let projectRepository = ProjectRepository(repo: repoName)
            let prService = PRService(repo: repoName)
            let statisticsService = StatisticsService(repo: repoName, projectRepository: projectRepository, prService: prService, workflowFile: workflowFileName)
            
            // Discover projects (CLI handles discovery, service handles collection)
            let projects = discoverProjects(configPath: configPath, baseBranch: baseBranchName, prService: prService)
            
            if projects.isEmpty {
                print("No projects found")
                gh.writeOutput(name: "has_statistics", value: "false")
                return
            }
            
            print()
            
            // Collect all statistics
            let report = statisticsService.collectAllStatistics(
                projects: projects,
                daysBack: daysBackValue,
                showAssigneeStats: showAssigneeStats
            )
            
            print("\n=== Collection Complete ===")
            print("Projects found: \(report.projectStats.count)")
            print("Team members tracked: \(report.teamStats.count)")
            print()
            
            // Generate outputs based on format
            if formatType == "slack" {
                // Generate Block Kit JSON for Slack webhook
                let slackPayload = report.formatForSlackBlocks(
                    showAssigneeStats: showAssigneeStats,
                    runUrl: runUrlValue.isEmpty ? nil : runUrlValue,
                    hideCompletedProjects: hideCompleted
                )
                
                do {
                    let slackJson = try JSONSerialization.data(withJSONObject: slackPayload, options: [.prettyPrinted])
                    let slackJsonString = String(data: slackJson, encoding: .utf8) ?? ""
                    
                    gh.writeOutput(name: "slack_message", value: slackJsonString)
                    gh.writeOutput(name: "has_statistics", value: "true")
                    gh.writeOutput(name: "slack_webhook_url", value: slackWebhookUrlValue)
                    print("=== Slack Output (Block Kit JSON) ===")
                    print(slackJsonString)
                    print()
                } catch {
                    throw ConfigurationError("Failed to serialize Slack payload: \(error)")
                }
            }
            
            if formatType == "json" || formatType == "slack" {
                // Always output JSON for programmatic access
                let jsonData = report.toJSON()
                gh.writeOutput(name: "statistics_json", value: jsonData)
            }
            
            // Write GitHub Step Summary
            gh.writeStepSummary(text: "# ClaudeChain Stats")
            gh.writeStepSummary(text: "")
            
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestamp = formatter.string(from: Date())
            gh.writeStepSummary(text: "*Generated: \(timestamp)*")
            gh.writeStepSummary(text: "")
            
            // Add leaderboard to step summary (only if enabled)
            if showAssigneeStats {
                let leaderboard = report.formatLeaderboard()
                if !leaderboard.isEmpty {
                    gh.writeStepSummary(text: leaderboard)
                    gh.writeStepSummary(text: "")
                }
            }
            
            // Add project summaries to step summary
            if !report.projectStats.isEmpty {
                gh.writeStepSummary(text: "## Project Progress")
                gh.writeStepSummary(text: "")
                for projectName in report.projectStats.keys.sorted() {
                    if let stats = report.projectStats[projectName] {
                        let summarySection = stats.toSummarySection()
                        let markdownFormatter = MarkdownReportFormatter()
                        let summary = markdownFormatter.formatSection(summarySection)
                        gh.writeStepSummary(text: summary)
                        gh.writeStepSummary(text: "")
                    }
                }
                
                // Add warnings section if there are projects needing attention
                let warningsSection = report.formatWarningsSection(forSlack: false)
                if !warningsSection.isEmpty {
                    gh.writeStepSummary(text: warningsSection)
                    gh.writeStepSummary(text: "")
                }
                
                // Add detailed task view with orphaned PRs
                gh.writeStepSummary(text: "## Detailed Task View")
                gh.writeStepSummary(text: "")
                gh.writeStepSummary(text: report.formatProjectDetails())
                gh.writeStepSummary(text: "")
            } else {
                gh.writeStepSummary(text: "## Project Progress")
                gh.writeStepSummary(text: "")
                gh.writeStepSummary(text: "*No projects found*")
                gh.writeStepSummary(text: "")
            }
            
            // Add team member summaries (detailed view, only if enabled)
            if showAssigneeStats {
                if !report.teamStats.isEmpty {
                    gh.writeStepSummary(text: "## Team Member Activity (Detailed)")
                    gh.writeStepSummary(text: "")
                    // Sort by activity level (merged PRs desc, then username)
                    let sortedMembers = report.teamStats.sorted { first, second in
                        if first.value.mergedCount != second.value.mergedCount {
                            return first.value.mergedCount > second.value.mergedCount
                        }
                        return first.key < second.key
                    }
                    for (_, stats) in sortedMembers {
                        let summary = stats.formatSummary()
                        gh.writeStepSummary(text: summary)
                        gh.writeStepSummary(text: "")
                    }
                } else {
                    gh.writeStepSummary(text: "## Team Member Activity")
                    gh.writeStepSummary(text: "")
                    gh.writeStepSummary(text: "*No team member activity found*")
                    gh.writeStepSummary(text: "")
                }
            }
            
            print("✅ Statistics generated successfully")
            
        } catch {
            gh.setError(message: "Statistics collection failed: \(error)")
            gh.writeOutput(name: "has_statistics", value: "false")
            gh.writeStepSummary(text: "# ClaudeChain Stats")
            gh.writeStepSummary(text: "")
            gh.writeStepSummary(text: "❌ **Error**: \(error)")
            print("Error: \(error)")
            throw ExitCode.failure
        }
    }
    
    private func discoverProjects(
        configPath: String?,
        baseBranch: String,
        prService: PRService
    ) -> [(String, String)] {
        if let configPath = configPath {
            // Single project mode
            print("Single project mode: \(configPath)")
            let project = Project.fromConfigPath(configPath)
            return [(project.name, baseBranch)]
        }
        
        // Multi-project mode - discover from labeled PRs
        print("Multi-project mode: discovering projects from GitHub PRs...")
        let projectBranches = prService.getUniqueProjects(label: "claudechain")
        print("Found \(projectBranches.count) unique project(s)")
        
        return Array(projectBranches)
    }
}