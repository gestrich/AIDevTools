import ClaudeChainService
import ClaudeChainSDK
import Foundation
import GitHubService

public struct WorkflowService {

    private let githubService: (any GitHubPRServiceProtocol)?

    public init() {
        self.githubService = nil
    }

    public init(githubService: any GitHubPRServiceProtocol) {
        self.githubService = githubService
    }

    public func triggerClaudeChainWorkflow(projectName: String, baseBranch: String, checkoutRef: String) throws {
        if let service = githubService {
            var triggerError: Error?
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                do {
                    try await service.triggerWorkflowDispatch(
                        workflowId: "claudechain.yml",
                        ref: checkoutRef,
                        inputs: [
                            ClaudeChainConstants.workflowProjectNameKey: projectName,
                            ClaudeChainConstants.workflowBaseBranchKey: baseBranch,
                            "checkout_ref": checkoutRef,
                        ]
                    )
                } catch let e {
                    triggerError = e
                }
                semaphore.signal()
            }
            semaphore.wait()
            if let error = triggerError {
                throw GitHubAPIError("Failed to trigger workflow for project '\(projectName)': \(error)")
            }
        } else {
            do {
                _ = try GitHubOperations.runGhCommand(args: [
                    "workflow", "run", "claudechain.yml",
                    "-f", "\(ClaudeChainConstants.workflowProjectNameKey)=\(projectName)",
                    "-f", "\(ClaudeChainConstants.workflowBaseBranchKey)=\(baseBranch)",
                    "-f", "checkout_ref=\(checkoutRef)",
                ])
            } catch {
                throw GitHubAPIError("Failed to trigger workflow for project '\(projectName)': \(error)")
            }
        }
    }

    public func batchTriggerClaudeChainWorkflows(projects: [String], baseBranch: String, checkoutRef: String) -> ([String], [String]) {
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
