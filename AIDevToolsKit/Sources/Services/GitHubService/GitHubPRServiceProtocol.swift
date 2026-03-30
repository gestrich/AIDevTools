import PRRadarModelsService

public protocol GitHubPRServiceProtocol: Sendable {
    func pullRequest(number: Int, useCache: Bool) async throws -> GitHubPullRequest
    func comments(number: Int, useCache: Bool) async throws -> GitHubPullRequestComments
    func repository(useCache: Bool) async throws -> GitHubRepository
    func updatePR(number: Int) async throws
    func updatePRs(numbers: [Int]) async throws
    func updateAllPRs() async throws -> [GitHubPullRequest]
    func updateRepository() async throws
    func writePR(_ pr: GitHubPullRequest, number: Int) async throws
    func writeComments(_ comments: GitHubPullRequestComments, number: Int) async throws
    func changes() -> AsyncStream<Int>
}
