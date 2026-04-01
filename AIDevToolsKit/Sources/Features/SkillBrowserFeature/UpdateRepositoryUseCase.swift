import Foundation
import RepositorySDK
import UseCaseSDK

public struct UpdateRepositoryUseCase: UseCase {
    private let store: RepositoryStore

    public init(store: RepositoryStore) {
        self.store = store
    }

    public func run(_ repository: RepositoryConfiguration) throws {
        try store.update(repository)
    }
}
