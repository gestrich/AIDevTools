import OctokitSDK
import PRRadarModelsService

public protocol GitHubAPIServiceProtocol: Sendable {
    func addAssignees(prNumber: Int, assignees: [String]) async throws
    func addLabels(prNumber: Int, labels: [String]) async throws
    func checkRuns(prNumber: Int, headSHA: String) async throws -> [GitHubCheckRun]
    func closePullRequest(number: Int) async throws
    func createLabel(name: String, color: String, description: String) async throws
    func createPullRequest(title: String, body: String, head: String, base: String, draft: Bool) async throws -> CreatedPullRequest
    func deleteBranch(branch: String) async throws
    func fileContent(path: String, ref: String) async throws -> String
    func getBranchHead(branch: String) async throws -> BranchHead
    func getFileContentWithSHA(path: String, ref: String) async throws -> (sha: String, content: String)
    func getGitTree(treeSHA: String) async throws -> [GitTreeEntry]
    func getPullRequest(number: Int) async throws -> GitHubPullRequest
    func getPullRequestComments(number: Int) async throws -> GitHubPullRequestComments
    func getRepository() async throws -> GitHubRepository
    func isMergeable(prNumber: Int) async throws -> Bool?
    func listBranches() async throws -> [String]
    func listDirectoryNames(path: String, ref: String) async throws -> [String]
    func listPullRequests(limit: Int, filter: PRFilter) async throws -> [GitHubPullRequest]
    func listReviews(prNumber: Int) async throws -> [GitHubReview]
    func listWorkflowRuns(workflow: String, branch: String?, limit: Int) async throws -> [WorkflowRun]
    func mergePullRequest(number: Int, mergeMethod: String) async throws
    func postIssueComment(number: Int, body: String) async throws
    func pullRequestByHeadBranch(branch: String) async throws -> CreatedPullRequest?
    func requestedReviewers(prNumber: Int) async throws -> [String]
    func requestReviewers(prNumber: Int, reviewers: [String]) async throws
    func triggerWorkflowDispatch(workflowId: String, ref: String, inputs: [String: String]) async throws
}
