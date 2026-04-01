import Foundation
import RepositorySDK

public struct MarkdownPlannerRepoSettingsStore: Sendable {
    private let repositoryStore: RepositoryStore

    public init(repositoryStore: RepositoryStore) {
        self.repositoryStore = repositoryStore
    }

    public func settings(forRepoId repoId: UUID) throws -> MarkdownPlannerRepoSettings? {
        try repositoryStore.find(byID: repoId)?.planner
    }

    public enum UpdateError: Error, LocalizedError {
        case emptyDirectory(String)

        public var errorDescription: String? {
            switch self {
            case .emptyDirectory(let field):
                return "\(field) cannot be an empty string; pass nil to use the default"
            }
        }
    }

    public func update(repoId: UUID, proposedDirectory: String?, completedDirectory: String?) throws {
        guard proposedDirectory?.isEmpty != true else {
            throw UpdateError.emptyDirectory("proposedDirectory")
        }
        guard completedDirectory?.isEmpty != true else {
            throw UpdateError.emptyDirectory("completedDirectory")
        }
        guard var repo = try repositoryStore.find(byID: repoId) else { return }
        repo.planner = MarkdownPlannerRepoSettings(
            proposedDirectory: proposedDirectory,
            completedDirectory: completedDirectory
        )
        try repositoryStore.update(repo)
    }

    public func remove(repoId: UUID) throws {
        guard var repo = try repositoryStore.find(byID: repoId) else { return }
        repo.planner = nil
        try repositoryStore.update(repo)
    }
}
