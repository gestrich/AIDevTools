import Foundation
import PRRadarModelsService

public struct GitHubPRService: GitHubPRServiceProtocol {
    private let cache: GitHubPRCache
    private let apiClient: any GitHubAPIClientProtocol
    private let changeStream: AsyncStream<Int>

    public init(rootURL: URL, apiClient: any GitHubAPIClientProtocol) {
        let prCache = GitHubPRCache(rootURL: rootURL)
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

    public func updateAllPRs() async throws -> [GitHubPullRequest] {
        let prs = try await apiClient.listPullRequests(limit: .max, filter: PRFilter())
        for pr in prs {
            try await cache.writePR(pr, number: pr.number)
        }
        return prs
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

    public func changes() -> AsyncStream<Int> {
        changeStream
    }
}
