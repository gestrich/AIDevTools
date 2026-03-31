import PRRadarModelsService

public protocol GitHubPRServiceProtocol: Sendable {
    func checkRuns(number: Int, useCache: Bool) async throws -> [GitHubCheckRun]
    func changes() -> AsyncStream<Int>
    func comments(number: Int, useCache: Bool) async throws -> GitHubPullRequestComments
    func isMergeable(number: Int) async throws -> Bool?
    func listPullRequests(limit: Int, filter: PRFilter) async throws -> [GitHubPullRequest]
    func pullRequest(number: Int, useCache: Bool) async throws -> GitHubPullRequest
    func readCachedIndex(key: String) async throws -> [Int]?
    func repository(useCache: Bool) async throws -> GitHubRepository
    func reviews(number: Int, useCache: Bool) async throws -> [GitHubReview]
    func updateAllPRs(filter: PRFilter) async throws -> [GitHubPullRequest]
    func updatePR(number: Int) async throws
    func updatePRs(numbers: [Int]) async throws
    func updateRepository() async throws
    func writeComments(_ comments: GitHubPullRequestComments, number: Int) async throws
    func writeCachedIndex(_ numbers: [Int], key: String) async throws
    func writePR(_ pr: GitHubPullRequest, number: Int) async throws
}
