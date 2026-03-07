import Foundation
import RepositorySDK

public struct UpdateRepositoryUseCase: Sendable {
    private let store: RepositoryStore

    public init(store: RepositoryStore) {
        self.store = store
    }

    public func run(_ repository: RepositoryInfo) throws {
        try store.update(repository)
    }
}
