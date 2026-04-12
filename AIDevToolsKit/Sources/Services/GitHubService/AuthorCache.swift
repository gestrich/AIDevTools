import Foundation

public struct AuthorCacheEntry: Codable, Sendable {
    public let login: String
    public let name: String
    public let avatarURL: String?

    public init(login: String, name: String, avatarURL: String? = nil) {
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
    }
}

public struct AuthorCache: Codable, Sendable {
    public var entries: [String: CacheRecord<AuthorCacheEntry>]

    public init(entries: [String: CacheRecord<AuthorCacheEntry>] = [:]) {
        self.entries = entries
    }
}
