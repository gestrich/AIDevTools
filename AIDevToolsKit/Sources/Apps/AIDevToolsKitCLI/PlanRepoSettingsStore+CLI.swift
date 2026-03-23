import Foundation
import PlanRunnerService
import RepositorySDK

extension PlanRepoSettingsStore {
    func resolvedProposedDirectory(forRepo repo: RepositoryInfo) throws -> URL {
        let settings = try settings(forRepoId: repo.id) ?? PlanRepoSettings(repoId: repo.id)
        return settings.resolvedProposedDirectory(repoPath: repo.path)
    }

    func resolvedCompletedDirectory(forRepo repo: RepositoryInfo) throws -> URL {
        let settings = try settings(forRepoId: repo.id) ?? PlanRepoSettings(repoId: repo.id)
        return settings.resolvedCompletedDirectory(repoPath: repo.path)
    }
}
