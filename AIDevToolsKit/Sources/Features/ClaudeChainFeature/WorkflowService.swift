/**
 * Composite service for GitHub workflow triggering.
 *
 * Provides workflow dispatch capabilities for triggering ClaudeChain workflows
 * programmatically. This service wraps the GitHub CLI workflow run command and
 * provides error handling for batch workflow triggering.
 */

import ClaudeChainService
import ClaudeChainSDK

public class WorkflowService {
    /**
     * Composite service for triggering GitHub workflows.
     *
     * This service provides workflow dispatch capabilities for the ClaudeChain
     * auto-start workflow and other use cases that need to trigger workflows
     * programmatically.
     *
     * Example:
     *     let service = WorkflowService()
     *     service.triggerClaudeChainWorkflow("test-project", "main", "main")
     *     // Or batch trigger
     *     let results = service.batchTriggerClaudeChainWorkflows(
     *         ["project1", "project2"],
     *         "main",
     *         "main"
     *     )
     */
    
    public init() {}
    
    public func triggerClaudeChainWorkflow(projectName: String, baseBranch: String, checkoutRef: String) throws {
        /**
         * Trigger the ClaudeChain workflow for a single project.
         *
         * Args:
         *     projectName: Name of the project to process
         *     baseBranch: Base branch to fetch specs from
         *     checkoutRef: Git ref to checkout
         *
         * Throws:
         *     GitHubAPIError: If workflow trigger fails
         *
         * Example:
         *     let service = WorkflowService()
         *     try service.triggerClaudeChainWorkflow(
         *         "my-refactor",
         *         "main",
         *         "main"
         *     )
         */
        do {
            _ = try GitHubOperations.runGhCommand(args: [
                "workflow", "run", "claudechain.yml",
                "-f", "\(ClaudeChainConstants.workflowProjectNameKey)=\(projectName)",
                "-f", "\(ClaudeChainConstants.workflowBaseBranchKey)=\(baseBranch)",
                "-f", "checkout_ref=\(checkoutRef)"
            ])
        } catch {
            throw GitHubAPIError("Failed to trigger workflow for project '\(projectName)': \(error)")
        }
    }
    
    public func batchTriggerClaudeChainWorkflows(projects: [String], baseBranch: String, checkoutRef: String) -> ([String], [String]) {
        /**
         * Trigger ClaudeChain workflow for multiple projects.
         *
         * Attempts to trigger workflows for all projects, collecting both
         * successes and failures. Does not raise on individual failures,
         * allowing batch processing to continue.
         *
         * Args:
         *     projects: List of project names to trigger
         *     baseBranch: Base branch to fetch specs from
         *     checkoutRef: Git ref to checkout
         *
         * Returns:
         *     Tuple of (successful_projects, failed_projects)
         *
         * Example:
         *     let service = WorkflowService()
         *     let (success, failed) = service.batchTriggerClaudeChainWorkflows(
         *         ["project1", "project2", "project3"],
         *         "main",
         *         "main"
         *     )
         *     print("Triggered: \(success.count), Failed: \(failed.count)")
         */
        var successful: [String] = []
        var failed: [String] = []
        
        for project in projects {
            do {
                try triggerClaudeChainWorkflow(projectName: project, baseBranch: baseBranch, checkoutRef: checkoutRef)
                successful.append(project)
                print("  ✅ Successfully triggered workflow for project: \(project)")
            } catch {
                failed.append(project)
                print("  ⚠️  Failed to trigger workflow for project '\(project)': \(error)")
            }
        }
        
        return (successful, failed)
    }
}