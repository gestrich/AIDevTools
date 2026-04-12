import Foundation

public struct GitHubRepoConfig: Sendable {
    public let account: String
    public let cacheURL: URL
    public let name: String
    public let repoPath: String
    public let token: String?

    public init(account: String, cacheURL: URL, name: String, repoPath: String, token: String?) {
        self.account = account
        self.cacheURL = cacheURL
        self.name = name
        self.repoPath = repoPath
        self.token = token
    }
}
