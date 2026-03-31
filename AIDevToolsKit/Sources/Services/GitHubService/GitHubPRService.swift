import Foundation
import PRRadarModelsService

public struct GitHubPRService: GitHubPRServiceProtocol {
    private let cache: GitHubPRCacheService
    private let apiClient: any GitHubAPIServiceProtocol
    private let changeStream: AsyncStream<Int>

    public init(rootURL: URL, apiClient: any GitHubAPIServiceProtocol) {
        let prCache = GitHubPRCacheService(rootURL: rootURL)
        self.cache = prCache
        self.changeStream = prCache.stream
        self.apiClient = apiClient
    }

    public func pullRequest(number: Int, useCache: Bool) async throws -> GitHubPullRequest {
        if useCache, let cached = try await cache.readPR(number: number) {
            return cached
        }
        let pr = try await apiClient.getPullRequest(number: number)
        try await cache.writePR(pr, number: number)
        return pr
    }

    public func comments(number: Int, useCache: Bool) async throws -> GitHubPullRequestComments {
        if useCache, let cached = try await cache.readComments(number: number) {
            return cached
        }
        let fetched = try await apiClient.getPullRequestComments(number: number)
        try await cache.writeComments(fetched, number: number)
        return fetched
    }

    public func repository(useCache: Bool) async throws -> GitHubRepository {
        if useCache, let cached = try await cache.readRepository() {
            return cached
        }
        let repo = try await apiClient.getRepository()
        try await cache.writeRepository(repo)
        return repo
    }

    public func updatePR(number: Int) async throws {
        let pr = try await apiClient.getPullRequest(number: number)
        try await cache.writePR(pr, number: number)
    }

    public func updatePRs(numbers: [Int]) async throws {
        for number in numbers {
            try await updatePR(number: number)
        }
    }

    public func listPullRequests(limit: Int, filter: PRFilter) async throws -> [GitHubPullRequest] {
        let prs = try await apiClient.listPullRequests(limit: limit, filter: filter)
        for pr in prs {
            try await cache.writePR(pr, number: pr.number)
        }
        return prs
    }

    public func updateAllPRs(filter: PRFilter) async throws -> [GitHubPullRequest] {
        try await listPullRequests(limit: .max, filter: filter)
    }

    public func updateRepository() async throws {
        let repo = try await apiClient.getRepository()
        try await cache.writeRepository(repo)
    }

    public func writePR(_ pr: GitHubPullRequest, number: Int) async throws {
        try await cache.writePR(pr, number: number)
    }

    public func writeComments(_ comments: GitHubPullRequestComments, number: Int) async throws {
        try await cache.writeComments(comments, number: number)
    }

    public func reviews(number: Int, useCache: Bool) async throws -> [GitHubReview] {
        if useCache, let cached = try await cache.readReviews(number: number) {
            return cached
        }
        let fetched = try await apiClient.listReviews(prNumber: number)
        try await cache.writeReviews(fetched, number: number)
        return fetched
    }

    public func checkRuns(number: Int, useCache: Bool) async throws -> [GitHubCheckRun] {
        if useCache, let cached = try await cache.readCheckRuns(number: number) {
            return cached
        }
        let pr = try await pullRequest(number: number, useCache: true)
        guard let headSHA = pr.headRefOid else {
            return []
        }
        let fetched = try await apiClient.checkRuns(prNumber: number, headSHA: headSHA)
        try await cache.writeCheckRuns(fetched, number: number)
        return fetched
    }

    public func isMergeable(number: Int) async throws -> Bool? {
        try await apiClient.isMergeable(prNumber: number)
    }

    public func readCachedIndex(key: String) async throws -> [Int]? {
        try await cache.readIndex(key: key)
    }

    public func writeCachedIndex(_ numbers: [Int], key: String) async throws {
        try await cache.writeIndex(numbers, key: key)
    }

    public func changes() -> AsyncStream<Int> {
        changeStream
    }
}
