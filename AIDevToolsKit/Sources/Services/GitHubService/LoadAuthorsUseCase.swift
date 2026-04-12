import Foundation
import Logging

private let logger = Logger(label: "LoadAuthorsUseCase")

public struct LoadAuthorsUseCase {

    private let config: GitHubRepoConfig

    public init(config: GitHubRepoConfig) {
        self.config = config
    }

    /// Cache-first lookup with 7-day TTL; fetches expired or missing logins via the GitHub API.
    public func execute(logins: Set<String>) async throws -> [String: AuthorCacheEntry] {
        let apiClient = try await GitHubServiceFactory.createGitHubAPI(
            repoPath: config.repoPath,
            githubAccount: config.account,
            explicitToken: config.token
        )
        let service = GitHubPRService(rootURL: config.cacheURL, apiClient: apiClient)

        var result: [String: AuthorCacheEntry] = [:]
        for login in logins where !login.isEmpty {
            if let cached = try await service.lookupAuthor(login: login) {
                result[login] = cached
            } else {
                do {
                    let author = try await apiClient.getUser(login: login)
                    let entry = AuthorCacheEntry(
                        login: login,
                        name: author.name ?? login,
                        avatarURL: author.avatarURL
                    )
                    try await service.updateAuthor(login: login, name: entry.name, avatarURL: entry.avatarURL)
                    result[login] = entry
                } catch {
                    logger.warning("execute(logins:): failed to fetch user \(login): \(error)")
                }
            }
        }
        return result
    }

    /// Returns all cached authors regardless of TTL — for filter dropdowns on repo load.
    public func executeAll() async throws -> [AuthorCacheEntry] {
        let apiClient = try await GitHubServiceFactory.createGitHubAPI(
            repoPath: config.repoPath,
            githubAccount: config.account,
            explicitToken: config.token
        )
        let service = GitHubPRService(rootURL: config.cacheURL, apiClient: apiClient)
        return try await service.loadAllAuthors()
    }
}
