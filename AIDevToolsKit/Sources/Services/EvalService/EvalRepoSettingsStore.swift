import Foundation
import RepositorySDK

public struct EvalRepoSettingsStore: Sendable {
    private let repositoryStore: RepositoryStore

    public init(repositoryStore: RepositoryStore) {
        self.repositoryStore = repositoryStore
    }

    public func settings(forRepoId repoId: UUID) throws -> EvalRepoSettings? {
        try repositoryStore.find(byID: repoId)?.eval
    }

    public func update(repoId: UUID, casesDirectory: String) throws {
        guard var repo = try repositoryStore.find(byID: repoId) else { return }
        repo.eval = EvalRepoSettings(casesDirectory: casesDirectory)
        try repositoryStore.update(repo)
    }

    public func remove(repoId: UUID) throws {
        guard var repo = try repositoryStore.find(byID: repoId) else { return }
        repo.eval = nil
        try repositoryStore.update(repo)
    }
}
