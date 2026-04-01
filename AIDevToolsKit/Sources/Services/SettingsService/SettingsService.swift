import DataPathsService
import Foundation
import RepositorySDK

public struct SettingsService: Sendable {
    public let repositoryStore: RepositoryStore

    public init(dataPathsService: DataPathsService) throws {
        let repositoriesFile = try dataPathsService.path(for: .repositories)
            .appending(path: "repositories.json")
        self.repositoryStore = RepositoryStore(repositoriesFile: repositoriesFile)
    }

    public func loadRepositories() throws -> [RepositoryConfiguration] {
        try repositoryStore.loadAll()
    }

    public func addRepository(_ repository: RepositoryConfiguration) throws {
        try repositoryStore.add(repository)
    }

    public func updateRepository(_ repository: RepositoryConfiguration) throws {
        try repositoryStore.update(repository)
    }

    public func removeRepository(id: UUID) throws {
        try repositoryStore.remove(id: id)
    }

    public func findRepository(byID id: UUID) throws -> RepositoryConfiguration? {
        try repositoryStore.find(byID: id)
    }

    public func findRepository(byPath path: URL) throws -> RepositoryConfiguration? {
        try repositoryStore.find(byPath: path)
    }
}
