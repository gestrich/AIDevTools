import ClaudeChainService
import Foundation
import GitHubService
import Logging

public struct WorkflowService {

    private let githubService: any GitHubPRServiceProtocol
    private let logger = Logger(label: "WorkflowService")

    public init(githubService: any GitHubPRServiceProtocol) {
        self.githubService = githubService
    }

    public func triggerClaudeChainWorkflow(
        projectName: String,
        baseBranch: String,
        checkoutRef: String,
        workflowFileName: String = "claude-chain.yml"
    ) async throws {
        do {
            try await githubService.triggerWorkflowDispatch(
                workflowId: workflowFileName,
                ref: checkoutRef,
                inputs: [
                    ClaudeChainConstants.workflowProjectNameKey: projectName,
                    ClaudeChainConstants.workflowBaseBranchKey: baseBranch,
                    "checkout_ref": checkoutRef,
                ]
            )
        } catch {
            throw GitHubAPIError("Failed to trigger workflow for project '\(projectName)': \(error)")
        }
    }

    public func batchTriggerClaudeChainWorkflows(
        projects: [String],
        baseBranch: String,
        checkoutRef: String,
        workflowFileName: String = "claude-chain.yml"
    ) async -> ([String], [String]) {
        var successful: [String] = []
        var failed: [String] = []

        for project in projects {
            do {
                try await triggerClaudeChainWorkflow(
                    projectName: project,
                    baseBranch: baseBranch,
                    checkoutRef: checkoutRef,
                    workflowFileName: workflowFileName
                )
                successful.append(project)
                logger.info("triggered workflow for project: \(project)")
            } catch {
                failed.append(project)
                logger.error("failed to trigger workflow for project '\(project)': \(error)")
            }
        }

        return (successful, failed)
    }
}
