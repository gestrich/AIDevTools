import Foundation
import RepositorySDK

public struct LoadRepositoriesUseCase: Sendable {
    private let store: RepositoryStore

    public init(store: RepositoryStore) {
        self.store = store
    }

    public func run() throws -> [RepositoryInfo] {
        try store.loadAll()
    }
}
