import ArgumentParser
import ClaudeChainService
import ClaudeChainInfrastructure
import Foundation

public struct PrepareSummaryCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "prepare-summary",
        abstract: "Prepare prompt for PR summary generation"
    )
    
    @Option(name: .long, help: "Pull request number")
    public var prNumber: String?
    
    @Option(name: .long, help: "Task description")
    public var task: String?
    
    @Option(name: .long, help: "Repository in format owner/repo")
    public var repo: String?
    
    @Option(name: .long, help: "GitHub Actions run ID")
    public var runId: String?
    
    @Option(name: .long, help: "Path to the action directory")
    public var actionPath: String?
    
    @Option(name: .long, help: "Base branch for git diff comparison")
    public var baseBranch: String?
    
    public init() {}
    
    public func run() throws {
        // Get environment variables
        let env = ProcessInfo.processInfo.environment
        
        // Use command line args first, fallback to environment variables
        let prNumber = self.prNumber ?? env["PR_NUMBER"]
        let task = self.task ?? env["TASK"]
        let repo = self.repo ?? env["GITHUB_REPOSITORY"]
        let runId = self.runId ?? env["GITHUB_RUN_ID"]
        let actionPath = self.actionPath ?? env["ACTION_PATH"]
        let baseBranch = self.baseBranch ?? env["BASE_BRANCH"]
        
        let exitCode = try cmdPrepareSummary(
            gh: GitHubActions(),
            prNumber: prNumber,
            task: task,
            repo: repo,
            runId: runId,
            actionPath: actionPath,
            baseBranch: baseBranch
        )
        
        if exitCode != 0 {
            throw ExitCode(Int32(exitCode))
        }
    }
    
    /// Handle 'prepare-summary' subcommand - generate prompt for PR summary comment
    ///
    /// This command generates a prompt for Claude Code to analyze changes and write
    /// a summary comment.
    ///
    /// All parameters passed explicitly, no environment variable access.
    ///
    /// - Parameters:
    ///   - gh: GitHub Actions helper instance
    ///   - prNumber: PR number to generate summary for
    ///   - task: Task description
    ///   - repo: GitHub repository (owner/name format)
    ///   - runId: GitHub Actions run ID
    ///   - actionPath: Path to the action directory
    ///   - baseBranch: Base branch for git diff comparison
    /// - Returns: Exit code (0 for success, non-zero for failure)
    private func cmdPrepareSummary(
        gh: GitHubActions,
        prNumber: String?,
        task: String?,
        repo: String?,
        runId: String?,
        actionPath: String?,
        baseBranch: String?
    ) throws -> Int {
        
        do {
            // Validate required inputs
            guard let prNumber = prNumber, !prNumber.isEmpty else {
                gh.setNotice(message: "No PR number provided, skipping summary generation")
                return 0  // Not an error, just skip
            }
            
            guard let task = task, !task.isEmpty else {
                gh.setError(message: "TASK environment variable is required")
                return 1
            }
            
            guard let repo = repo, !repo.isEmpty,
                  let runId = runId, !runId.isEmpty else {
                gh.setError(message: "GITHUB_REPOSITORY and GITHUB_RUN_ID are required")
                return 1
            }
            
            guard let baseBranch = baseBranch, !baseBranch.isEmpty else {
                gh.setError(message: "BASE_BRANCH environment variable is required")
                return 1
            }
            
            // Construct workflow URL
            let workflowUrl = "https://github.com/\(repo)/actions/runs/\(runId)"
            
            // Load prompt template
            // Use new resources path in src/claudechain/resources/prompts/
            let actionPathStr = actionPath ?? ""
            let templatePath = "\(actionPathStr)/src/claudechain/resources/prompts/summary_prompt.md"
            
            let template: String
            do {
                template = try String(contentsOfFile: templatePath, encoding: .utf8)
            } catch {
                gh.setError(message: "Prompt template not found: \(templatePath)")
                return 1
            }
            
            // Substitute variables in template
            var summaryPrompt = template
            summaryPrompt = summaryPrompt.replacingOccurrences(of: "{TASK_DESCRIPTION}", with: task)
            summaryPrompt = summaryPrompt.replacingOccurrences(of: "{PR_NUMBER}", with: prNumber)
            summaryPrompt = summaryPrompt.replacingOccurrences(of: "{WORKFLOW_URL}", with: workflowUrl)
            summaryPrompt = summaryPrompt.replacingOccurrences(of: "{SUMMARY_FILE_PATH}", with: Constants.prSummaryFilePath)
            summaryPrompt = summaryPrompt.replacingOccurrences(of: "{BASE_BRANCH}", with: baseBranch)
            
            // Get summary schema JSON
            guard let summaryJsonSchema = ClaudeSchemas.getSummaryTaskSchemaJSON() else {
                gh.setError(message: "Failed to generate summary task schema JSON")
                return 1
            }
            
            // Write output
            gh.writeOutput(name: "summary_prompt", value: summaryPrompt)
            gh.writeOutput(name: "summary_file", value: Constants.prSummaryFilePath)
            gh.writeOutput(name: "summary_json_schema", value: summaryJsonSchema)
            
            print("✅ Summary prompt prepared for PR #\(prNumber)")
            print("   Task: \(task)")
            print("   Prompt length: \(summaryPrompt.count) characters")
            
            return 0
            
        } catch {
            gh.setError(message: "Failed to prepare summary: \(error.localizedDescription)")
            print("Error: \(error)")
            if let nsError = error as NSError? {
                print("  Domain: \(nsError.domain)")
                print("  Code: \(nsError.code)")
                print("  UserInfo: \(nsError.userInfo)")
            }
            return 1
        }
    }
}