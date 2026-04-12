import ClaudeChainFeature
import ClaudeChainService
import Foundation
import GitHubService
import OctokitSDK
import PRRadarModelsService
import Testing

@Suite("WorkflowService")
struct WorkflowServiceTests {

    // MARK: - batchTriggerClaudeChainWorkflows

    @Test("empty project list returns empty arrays")
    func batchTriggerEmptyList() {
        let service = WorkflowService(githubService: FailingGitHubPRService())
        let (successful, failed) = service.batchTriggerClaudeChainWorkflows(
            projects: [],
            baseBranch: "main",
            checkoutRef: "main"
        )
        #expect(successful.isEmpty)
        #expect(failed.isEmpty)
    }

    @Test("single failing project goes to failed list")
    func batchTriggerSingleProject() {
        let service = WorkflowService(githubService: FailingGitHubPRService())
        let (successful, failed) = service.batchTriggerClaudeChainWorkflows(
            projects: ["project1"],
            baseBranch: "main",
            checkoutRef: "main"
        )
        #expect(successful.isEmpty)
        #expect(failed == ["project1"])
    }

    @Test("multiple failing projects all go to failed list")
    func batchTriggerMultipleProjects() {
        let service = WorkflowService(githubService: FailingGitHubPRService())
        let projects = ["project1", "project2", "project3"]
        let (successful, failed) = service.batchTriggerClaudeChainWorkflows(
            projects: projects,
            baseBranch: "main",
            checkoutRef: "main"
        )
        #expect(successful.isEmpty)
        #expect(Set(failed) == Set(projects))
    }

    @Test("successful.count + failed.count equals input count")
    func batchTriggerCountInvariant() {
        let service = WorkflowService(githubService: FailingGitHubPRService())
        let projects = ["p1", "p2", "p3", "p4"]
        let (successful, failed) = service.batchTriggerClaudeChainWorkflows(
            projects: projects,
            baseBranch: "main",
            checkoutRef: "main"
        )
        #expect(successful.count + failed.count == projects.count)
    }

    // MARK: - triggerClaudeChainWorkflow

    @Test("trigger wraps service error in GitHubAPIError")
    func triggerWrapsErrorInGitHubAPIError() throws {
        let service = WorkflowService(githubService: FailingGitHubPRService())
        #expect(throws: GitHubAPIError.self) {
            try service.triggerClaudeChainWorkflow(
                projectName: "test-project",
                baseBranch: "main",
                checkoutRef: "main"
            )
        }
    }

    @Test("GitHubAPIError message names the project")
    func triggerErrorMessageNamesProject() {
        let service = WorkflowService(githubService: FailingGitHubPRService())
        do {
            try service.triggerClaudeChainWorkflow(
                projectName: "my-refactor",
                baseBranch: "main",
                checkoutRef: "main"
            )
        } catch let error as GitHubAPIError {
            #expect(error.message.contains("my-refactor"))
        } catch {
            Issue.record("Expected GitHubAPIError, got \(type(of: error))")
        }
    }
}

// MARK: - Test doubles

private final class FailingGitHubPRService: GitHubPRServiceProtocol {
    private struct Unimplemented: Error {}

    func triggerWorkflowDispatch(workflowId: String, ref: String, inputs: [String: String]) async throws {
        throw Unimplemented()
    }

    func branchHead(branch: String, ttl: Foundation.TimeInterval) async throws -> BranchHead { throw Unimplemented() }
    func changes() -> AsyncStream<Int> { AsyncStream { _ in } }
    func checkRuns(number: Int, useCache: Bool) async throws -> [GitHubCheckRun] { throw Unimplemented() }
    func closePullRequest(number: Int) async throws { throw Unimplemented() }
    func comments(number: Int, useCache: Bool) async throws -> GitHubPullRequestComments { throw Unimplemented() }
    func createLabel(name: String, color: String, description: String) async throws { throw Unimplemented() }
    func createPullRequest(title: String, body: String, head: String, base: String, draft: Bool, labels: [String], assignees: [String], reviewers: [String]) async throws -> CreatedPullRequest { throw Unimplemented() }
    func deleteBranch(branch: String) async throws { throw Unimplemented() }
    func fileBlob(blobSHA: String, path: String, ref: String) async throws -> String { throw Unimplemented() }
    func fileContent(path: String, ref: String) async throws -> String { throw Unimplemented() }
    func gitTree(treeSHA: String) async throws -> [GitTreeEntry] { throw Unimplemented() }
    func isMergeable(number: Int) async throws -> Bool? { throw Unimplemented() }
    func listBranches(ttl: Foundation.TimeInterval) async throws -> [String] { throw Unimplemented() }
    func listDirectoryNames(path: String, ref: String) async throws -> [String] { throw Unimplemented() }
    func listPullRequests(limit: Int, filter: PRFilter) async throws -> [PRRadarModelsService.GitHubPullRequest] { throw Unimplemented() }
    func listWorkflowRuns(workflow: String, branch: String?, limit: Int, ttl: Foundation.TimeInterval) async throws -> [OctokitSDK.WorkflowRun] { throw Unimplemented() }
    func mergePullRequest(number: Int, mergeMethod: String) async throws { throw Unimplemented() }
    func postIssueComment(prNumber: Int, body: String) async throws { throw Unimplemented() }
    func pullRequest(number: Int, useCache: Bool) async throws -> PRRadarModelsService.GitHubPullRequest { throw Unimplemented() }
    func pullRequestByHeadBranch(branch: String) async throws -> CreatedPullRequest? { throw Unimplemented() }
    func readCachedIndex(key: String) async throws -> [Int]? { throw Unimplemented() }
    func repository(useCache: Bool) async throws -> GitHubRepository { throw Unimplemented() }
    func reviews(number: Int, useCache: Bool) async throws -> [GitHubReview] { throw Unimplemented() }
    func updatePRs(filter: PRFilter) async throws -> [PRRadarModelsService.GitHubPullRequest] { throw Unimplemented() }
    func updatePR(number: Int) async throws { throw Unimplemented() }
    func updatePRs(numbers: [Int]) async throws { throw Unimplemented() }
    func updateRepository() async throws { throw Unimplemented() }
    func writeComments(_ comments: GitHubPullRequestComments, number: Int) async throws { throw Unimplemented() }
    func writeCachedIndex(_ numbers: [Int], key: String) async throws { throw Unimplemented() }
    func writePR(_ pr: PRRadarModelsService.GitHubPullRequest, number: Int) async throws { throw Unimplemented() }
}
