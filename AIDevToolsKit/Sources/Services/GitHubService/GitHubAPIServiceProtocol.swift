import PRRadarModelsService

public protocol GitHubAPIServiceProtocol: Sendable {
    func checkRuns(prNumber: Int, headSHA: String) async throws -> [GitHubCheckRun]
    func fileContent(path: String, ref: String) async throws -> String
    func listDirectoryNames(path: String, ref: String) async throws -> [String]
    func getPullRequest(number: Int) async throws -> GitHubPullRequest
    func getPullRequestComments(number: Int) async throws -> GitHubPullRequestComments
    func getRepository() async throws -> GitHubRepository
    func isMergeable(prNumber: Int) async throws -> Bool?
    func listPullRequests(limit: Int, filter: PRFilter) async throws -> [GitHubPullRequest]
    func listReviews(prNumber: Int) async throws -> [GitHubReview]
    func requestedReviewers(prNumber: Int) async throws -> [String]
}
