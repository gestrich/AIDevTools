import ClaudeChainFeature
import ClaudeChainService
import Foundation
import GitHubService
import OctokitSDK
import Testing

@Suite("WorkflowService")
struct WorkflowServiceTests {

    // MARK: - batchTriggerClaudeChainWorkflows

    @Test("empty project list returns empty arrays")
    func batchTriggerEmptyList() async {
        let service = WorkflowService(githubService: FailingGitHubPRService())
        let (successful, failed) = await service.batchTriggerClaudeChainWorkflows(
            projects: [],
            baseBranch: "main",
            checkoutRef: "main"
        )
        #expect(successful.isEmpty)
        #expect(failed.isEmpty)
    }

    @Test("single failing project goes to failed list")
    func batchTriggerSingleProject() async {
        let service = WorkflowService(githubService: FailingGitHubPRService())
        let (successful, failed) = await service.batchTriggerClaudeChainWorkflows(
            projects: ["project1"],
            baseBranch: "main",
            checkoutRef: "main"
        )
        #expect(successful.isEmpty)
        #expect(failed == ["project1"])
    }

    @Test("multiple failing projects all go to failed list")
    func batchTriggerMultipleProjects() async {
        let service = WorkflowService(githubService: FailingGitHubPRService())
        let projects = ["project1", "project2", "project3"]
        let (successful, failed) = await service.batchTriggerClaudeChainWorkflows(
            projects: projects,
            baseBranch: "main",
            checkoutRef: "main"
        )
        #expect(successful.isEmpty)
        #expect(Set(failed) == Set(projects))
    }

    @Test("successful.count + failed.count equals input count")
    func batchTriggerCountInvariant() async {
        let service = WorkflowService(githubService: FailingGitHubPRService())
        let projects = ["p1", "p2", "p3", "p4"]
        let (successful, failed) = await service.batchTriggerClaudeChainWorkflows(
            projects: projects,
            baseBranch: "main",
            checkoutRef: "main"
        )
        #expect(successful.count + failed.count == projects.count)
    }

    // MARK: - triggerClaudeChainWorkflow

    @Test("trigger wraps service error in GitHubAPIError")
    func triggerWrapsErrorInGitHubAPIError() async throws {
        let service = WorkflowService(githubService: FailingGitHubPRService())
        await #expect(throws: GitHubAPIError.self) {
            try await service.triggerClaudeChainWorkflow(
                projectName: "test-project",
                baseBranch: "main",
                checkoutRef: "main"
            )
        }
    }

    @Test("GitHubAPIError message names the project")
    func triggerErrorMessageNamesProject() async throws {
        let service = WorkflowService(githubService: FailingGitHubPRService())
        let error = try await #require(throws: GitHubAPIError.self) {
            try await service.triggerClaudeChainWorkflow(
                projectName: "my-refactor",
                baseBranch: "main",
                checkoutRef: "main"
            )
        }
        #expect(error.message.contains("my-refactor"))
    }

    @Test("trigger uses default workflow file name")
    func triggerUsesDefaultWorkflowFileName() async throws {
        let githubService = RecordingGitHubPRService()
        let service = WorkflowService(githubService: githubService)

        try await service.triggerClaudeChainWorkflow(
            projectName: "test-project",
            baseBranch: "main",
            checkoutRef: "HEAD"
        )

        let dispatches = githubService.dispatches()
        #expect(dispatches.count == 1)
        #expect(dispatches[0].workflowId == "claude-chain.yml")
    }

    @Test("batch trigger forwards custom workflow file name")
    func batchTriggerForwardsCustomWorkflowFileName() async {
        let githubService = RecordingGitHubPRService()
        let service = WorkflowService(githubService: githubService)

        let (successful, failed) = await service.batchTriggerClaudeChainWorkflows(
            projects: ["project1", "project2"],
            baseBranch: "release",
            checkoutRef: "HEAD",
            workflowFileName: "custom-workflow.yml"
        )

        let dispatches = githubService.dispatches()
        #expect(successful == ["project1", "project2"])
        #expect(failed.isEmpty)
        #expect(dispatches.count == 2)
        #expect(dispatches.allSatisfy { $0.workflowId == "custom-workflow.yml" })
        #expect(dispatches.allSatisfy { $0.ref == "HEAD" })
        #expect(dispatches.allSatisfy { $0.inputs[ClaudeChainConstants.workflowBaseBranchKey] == "release" })
    }
}

// MARK: - Test doubles

private struct WorkflowDispatchRecord: Sendable {
    let workflowId: String
    let ref: String
    let inputs: [String: String]
}

private struct FailingGitHubPRService: GitHubPRServiceProtocol {
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
    func listPullRequests(limit: Int, filter: PRFilter) async throws -> [GitHubService.GitHubPullRequest] { throw Unimplemented() }
    func listWorkflowRuns(workflow: String, branch: String?, limit: Int, ttl: Foundation.TimeInterval) async throws -> [OctokitSDK.WorkflowRun] { throw Unimplemented() }
    func mergePullRequest(number: Int, mergeMethod: String) async throws { throw Unimplemented() }
    func postIssueComment(prNumber: Int, body: String) async throws { throw Unimplemented() }
    func pullRequest(number: Int, useCache: Bool) async throws -> GitHubService.GitHubPullRequest { throw Unimplemented() }
    func pullRequestByHeadBranch(branch: String) async throws -> CreatedPullRequest? { throw Unimplemented() }
    func readAllCachedPRs() async -> [GitHubService.GitHubPullRequest] { [] }
    func readCachedIndex(key: String) async throws -> [Int]? { throw Unimplemented() }
    func readCacheRefreshState() async throws -> CacheRefreshState? { throw Unimplemented() }
    func repository(useCache: Bool) async throws -> GitHubRepository { throw Unimplemented() }
    func reviews(number: Int, useCache: Bool) async throws -> [GitHubReview] { throw Unimplemented() }
    func updatePRs(filter: PRFilter) async throws -> [GitHubService.GitHubPullRequest] { throw Unimplemented() }
    func updatePR(number: Int) async throws { throw Unimplemented() }
    func updatePRs(numbers: [Int]) async throws { throw Unimplemented() }
    func updateRepository() async throws { throw Unimplemented() }
    func writeComments(_ comments: GitHubPullRequestComments, number: Int) async throws { throw Unimplemented() }
    func writeCachedIndex(_ numbers: [Int], key: String) async throws { throw Unimplemented() }
    func writeCacheRefreshState(_ state: CacheRefreshState) async throws { throw Unimplemented() }
    func writePR(_ pr: GitHubService.GitHubPullRequest, number: Int) async throws { throw Unimplemented() }
}

private final class RecordingGitHubPRService: GitHubPRServiceProtocol, @unchecked Sendable {
    private struct Unimplemented: Error {}

    private let lock = NSLock()
    private var recordedDispatches: [WorkflowDispatchRecord] = []

    func dispatches() -> [WorkflowDispatchRecord] {
        lock.withLock {
            recordedDispatches
        }
    }

    func triggerWorkflowDispatch(workflowId: String, ref: String, inputs: [String : String]) async throws {
        lock.withLock {
            recordedDispatches.append(
                WorkflowDispatchRecord(
                    workflowId: workflowId,
                    ref: ref,
                    inputs: inputs
                )
            )
        }
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
    func listPullRequests(limit: Int, filter: PRFilter) async throws -> [GitHubService.GitHubPullRequest] { throw Unimplemented() }
    func listWorkflowRuns(workflow: String, branch: String?, limit: Int, ttl: Foundation.TimeInterval) async throws -> [OctokitSDK.WorkflowRun] { throw Unimplemented() }
    func mergePullRequest(number: Int, mergeMethod: String) async throws { throw Unimplemented() }
    func postIssueComment(prNumber: Int, body: String) async throws { throw Unimplemented() }
    func pullRequest(number: Int, useCache: Bool) async throws -> GitHubService.GitHubPullRequest { throw Unimplemented() }
    func pullRequestByHeadBranch(branch: String) async throws -> CreatedPullRequest? { throw Unimplemented() }
    func readAllCachedPRs() async -> [GitHubService.GitHubPullRequest] { [] }
    func readCachedIndex(key: String) async throws -> [Int]? { throw Unimplemented() }
    func readCacheRefreshState() async throws -> CacheRefreshState? { throw Unimplemented() }
    func repository(useCache: Bool) async throws -> GitHubRepository { throw Unimplemented() }
    func reviews(number: Int, useCache: Bool) async throws -> [GitHubReview] { throw Unimplemented() }
    func updatePR(number: Int) async throws { throw Unimplemented() }
    func updatePRs(filter: PRFilter) async throws -> [GitHubService.GitHubPullRequest] { throw Unimplemented() }
    func updatePRs(numbers: [Int]) async throws { throw Unimplemented() }
    func updateRepository() async throws { throw Unimplemented() }
    func writeComments(_ comments: GitHubPullRequestComments, number: Int) async throws { throw Unimplemented() }
    func writeCachedIndex(_ numbers: [Int], key: String) async throws { throw Unimplemented() }
    func writeCacheRefreshState(_ state: CacheRefreshState) async throws { throw Unimplemented() }
    func writePR(_ pr: GitHubService.GitHubPullRequest, number: Int) async throws { throw Unimplemented() }
}
