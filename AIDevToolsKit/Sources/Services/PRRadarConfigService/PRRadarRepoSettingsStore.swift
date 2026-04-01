import Foundation
import RepositorySDK

public struct PRRadarRepoSettingsStore: Sendable {
    private let repositoryStore: RepositoryStore

    public init(repositoryStore: RepositoryStore) {
        self.repositoryStore = repositoryStore
    }

    public func settings(forRepoId repoId: UUID) throws -> PRRadarRepoSettings? {
        try repositoryStore.find(byID: repoId)?.prradar
    }

    public func update(repoId: UUID, rulePaths: [RulePath], diffSource: DiffSource, agentScriptPath: String = "") throws {
        guard var repo = try repositoryStore.find(byID: repoId) else { return }
        repo.prradar = PRRadarRepoSettings(rulePaths: rulePaths, diffSource: diffSource, agentScriptPath: agentScriptPath)
        try repositoryStore.update(repo)
    }

    public func remove(repoId: UUID) throws {
        guard var repo = try repositoryStore.find(byID: repoId) else { return }
        repo.prradar = nil
        try repositoryStore.update(repo)
    }
}
