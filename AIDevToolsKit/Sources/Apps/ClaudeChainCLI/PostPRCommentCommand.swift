import ArgumentParser
import ClaudeChainSDK
import ClaudeChainService
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct PostPRCommentCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "post-pr-comment",
        abstract: "Post unified PR comment with summary and cost breakdown"
    )
    
    @Option(name: .long, help: "Pull request number")
    public var prNumber: String
    
    @Option(name: .long, help: "Path to file containing AI-generated summary")
    public var summaryFilePath: String
    
    @Option(name: .long, help: "Path to main execution file")
    public var mainExecutionFile: String
    
    @Option(name: .long, help: "Path to summary execution file")
    public var summaryExecutionFile: String
    
    @Option(name: .long, help: "Repository in format owner/repo")
    public var repo: String
    
    @Option(name: .long, help: "Workflow run ID")
    public var runId: String
    
    @Option(name: .long, help: "Task description (for workflow summary)")
    public var task: String = ""
    
    public init() {}
    
    public func run() throws {
        let exitCode = try cmdPostPRComment(
            gh: GitHubActions(),
            prNumber: prNumber,
            summaryFilePath: summaryFilePath,
            mainExecutionFile: mainExecutionFile,
            summaryExecutionFile: summaryExecutionFile,
            repo: repo,
            runId: runId,
            task: task
        )
        
        if exitCode != 0 {
            throw ExitCode(Int32(exitCode))
        }
    }
    
    /// Post a unified comment with PR summary and cost breakdown.
    ///
    /// All parameters passed explicitly, no environment variable access.
    ///
    /// - Parameters:
    ///   - gh: GitHub Actions helper for outputs and errors
    ///   - prNumber: Pull request number
    ///   - summaryFilePath: Path to file containing AI-generated summary
    ///   - mainExecutionFile: Path to main execution file
    ///   - summaryExecutionFile: Path to summary execution file
    ///   - repo: Repository in format owner/repo
    ///   - runId: Workflow run ID
    ///   - task: Task description (for workflow summary)
    /// - Returns: 0 on success, 1 on error
    ///
    /// Outputs:
    ///   - comment_posted: "true" if comment was posted, "false" otherwise
    ///   - cost_breakdown: JSON string with complete cost breakdown (CostBreakdown.toJson())
    private func cmdPostPRComment(
        gh: GitHubActions,
        prNumber: String,
        summaryFilePath: String,
        mainExecutionFile: String,
        summaryExecutionFile: String,
        repo: String,
        runId: String,
        task: String = ""
    ) throws -> Int {
        // Strip whitespace from inputs
        let prNumber = prNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryFilePath = summaryFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let mainExecutionFile = mainExecutionFile.trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryExecutionFile = summaryExecutionFile.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        let runId = runId.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = task.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If no PR number, skip gracefully
        if prNumber.isEmpty {
            print("::notice::No PR number provided, skipping PR comment")
            gh.writeOutput(name: "comment_posted", value: "false")
            return 0
        }
        
        if repo.isEmpty {
            gh.setError(message: "GITHUB_REPOSITORY environment variable is required")
            return 1
        }
        
        if runId.isEmpty {
            gh.setError(message: "GITHUB_RUN_ID environment variable is required")
            return 1
        }
        
        do {
            // Extract costs from execution files
            let costBreakdown = try CostBreakdown.fromExecutionFiles(
                mainExecutionFile: mainExecutionFile,
                summaryExecutionFile: summaryExecutionFile
            )
            
            // Output complete cost breakdown for downstream steps (single structured output)
            gh.writeOutput(name: "cost_breakdown", value: try costBreakdown.toJSON())
            
            // Use domain models for parsing and formatting
            let summary = SummaryFile.fromFile(summaryFilePath)
            
            // Create report and format comment using domain model
            let prURL = "https://github.com/\(repo)/pull/\(prNumber)"
            let report = PullRequestCreatedReport(
                prNumber: prNumber,
                prURL: prURL,
                projectName: "",  // Not shown in PR comment
                task: task,
                costBreakdown: costBreakdown,
                repo: repo,
                runID: runId,
                summaryContent: summary.hasContent ? summary.content : nil
            )
            
            let formatter = MarkdownReportFormatter()
            let comment = formatter.format(report.buildCommentElements())
            
            // Post comment to PR
            print("Posting PR comment to PR #\(prNumber)...")

            do {
                guard let prNum = Int(prNumber) else {
                    gh.setError(message: "Invalid PR number: '\(prNumber)'")
                    return 1
                }
                try postPRComment(repo: repo, prNumber: prNum, body: comment)
                
                print("✅ PR comment posted to PR #\(prNumber)")
                if summary.hasContent {
                    print("   - AI-generated summary included")
                }
                print("   - Main task: \(Formatting.formatUSD(costBreakdown.mainCost))")
                print("   - PR summary: \(Formatting.formatUSD(costBreakdown.summaryCost))")
                print("   - Total: \(Formatting.formatUSD(costBreakdown.totalCost))")
                
                // Write workflow summary to GITHUB_STEP_SUMMARY
                let workflowSummary = formatter.format(report.buildWorkflowSummaryElements())
                gh.writeStepSummary(text: workflowSummary)
                
                gh.writeOutput(name: "comment_posted", value: "true")
                return 0
                
            } catch {
                gh.setError(message: "Failed to post comment: \(error.localizedDescription)")
                return 1
            }
            
        } catch {
            gh.setError(message: "Error posting PR comment: \(error.localizedDescription)")
            return 1
        }
    }

    private func postPRComment(repo: String, prNumber: Int, body: String) throws {
        let env = ProcessInfo.processInfo.environment
        guard let token = env["GH_TOKEN"] ?? env["GITHUB_TOKEN"] else {
            throw GitHubAPIError("No GH_TOKEN or GITHUB_TOKEN environment variable set")
        }
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/issues/\(prNumber)/comments") else {
            throw GitHubAPIError("Invalid repository: \(repo)")
        }
        let bodyJSON = try JSONSerialization.data(withJSONObject: ["body": body])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyJSON

        var responseError: Error?
        var statusCode = 0
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, response, error in
            responseError = error
            statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let error = responseError {
            throw GitHubAPIError("Failed to post PR comment: \(error.localizedDescription)")
        }
        if statusCode < 200 || statusCode >= 300 {
            throw GitHubAPIError("GitHub API returned status \(statusCode) when posting PR comment")
        }
    }
}