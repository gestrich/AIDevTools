import Foundation

public struct CacheRecord<T: Codable & Sendable>: Codable, Sendable {
    public let value: T
    public let cachedAt: Date

    public init(value: T, cachedAt: Date = Date()) {
        self.value = value
        self.cachedAt = cachedAt
    }

    public func isExpired(ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(cachedAt) > ttl
    }

    public func valueIfFresh(ttl: TimeInterval) -> T? {
        isExpired(ttl: ttl) ? nil : value
    }
}
