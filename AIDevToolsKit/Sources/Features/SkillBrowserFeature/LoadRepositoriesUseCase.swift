import Foundation
import RepositorySDK
import UseCaseSDK

public struct LoadRepositoriesUseCase: UseCase {
    private let store: RepositoryStore

    public init(store: RepositoryStore) {
        self.store = store
    }

    public func run() throws -> [RepositoryInfo] {
        try store.loadAll()
    }
}
