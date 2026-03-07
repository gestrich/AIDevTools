import Foundation
import RepositorySDK

public struct RemoveRepositoryUseCase: Sendable {
    private let store: RepositoryStore

    public init(store: RepositoryStore) {
        self.store = store
    }

    public func run(id: UUID) throws {
        try store.remove(id: id)
    }
}
