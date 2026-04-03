import Foundation
import OctokitSDK
import PRRadarModelsService

public protocol GitHubPRServiceProtocol: Sendable {
    func branchHead(branch: String, ttl: TimeInterval) async throws -> BranchHead
    func checkRuns(number: Int, useCache: Bool) async throws -> [GitHubCheckRun]
    func changes() -> AsyncStream<Int>
    func fileBlob(blobSHA: String, path: String, ref: String) async throws -> String
    func fileContent(path: String, ref: String) async throws -> String
    func gitTree(treeSHA: String) async throws -> [GitTreeEntry]
    func listDirectoryNames(path: String, ref: String) async throws -> [String]
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
