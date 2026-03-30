import Foundation
import RepositorySDK
import UseCaseSDK

public struct RemoveRepositoryUseCase: UseCase {
    private let store: RepositoryStore

    public init(store: RepositoryStore) {
        self.store = store
    }

    public func run(id: UUID) throws {
        try store.remove(id: id)
    }
}
