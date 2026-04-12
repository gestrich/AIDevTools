import Foundation
import OctokitSDK
import PRRadarModelsService

public protocol GitHubPRServiceProtocol: Sendable {
    func branchHead(branch: String, ttl: TimeInterval) async throws -> BranchHead
    func changes() -> AsyncStream<Int>
    func readAllCachedPRs() async -> [GitHubPullRequest]
    func checkRuns(number: Int, useCache: Bool) async throws -> [GitHubCheckRun]
    func closePullRequest(number: Int) async throws
    func comments(number: Int, useCache: Bool) async throws -> GitHubPullRequestComments
    func createLabel(name: String, color: String, description: String) async throws
    func createPullRequest(title: String, body: String, head: String, base: String, draft: Bool, labels: [String], assignees: [String], reviewers: [String]) async throws -> CreatedPullRequest
    func deleteBranch(branch: String) async throws
    func fileBlob(blobSHA: String, path: String, ref: String) async throws -> String
    func fileContent(path: String, ref: String) async throws -> String
    func gitTree(treeSHA: String) async throws -> [GitTreeEntry]
    func isMergeable(number: Int) async throws -> Bool?
    func listBranches(ttl: TimeInterval) async throws -> [String]
    func listDirectoryNames(path: String, ref: String) async throws -> [String]
    func listPullRequests(limit: Int, filter: PRFilter) async throws -> [GitHubPullRequest]
    func listWorkflowRuns(workflow: String, branch: String?, limit: Int, ttl: TimeInterval) async throws -> [WorkflowRun]
    func mergePullRequest(number: Int, mergeMethod: String) async throws
    func postIssueComment(prNumber: Int, body: String) async throws
    func pullRequest(number: Int, useCache: Bool) async throws -> GitHubPullRequest
    func pullRequestByHeadBranch(branch: String) async throws -> CreatedPullRequest?
    func readCachedIndex(key: String) async throws -> [Int]?
    func repository(useCache: Bool) async throws -> GitHubRepository
    func reviews(number: Int, useCache: Bool) async throws -> [GitHubReview]
    func triggerWorkflowDispatch(workflowId: String, ref: String, inputs: [String: String]) async throws
    func updatePRs(filter: PRFilter) async throws -> [GitHubPullRequest]
    func updatePR(number: Int) async throws
    func updatePRs(numbers: [Int]) async throws
    func updateRepository() async throws
    func writeComments(_ comments: GitHubPullRequestComments, number: Int) async throws
    func writeCachedIndex(_ numbers: [Int], key: String) async throws
    func writePR(_ pr: GitHubPullRequest, number: Int) async throws
}
