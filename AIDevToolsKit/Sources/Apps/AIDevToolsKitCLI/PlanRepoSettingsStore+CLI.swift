import Foundation
import PlanRunnerService
import RepositorySDK

extension PlanRepoSettingsStore {
    static func fromCLI(dataPath: String?) -> PlanRepoSettingsStore {
        let path = RepositoryStore.cliDataPath(from: dataPath)
        return PlanRepoSettingsStore(filePath: path.appending(path: "plan-settings.json"))
    }

    func resolvedProposedDirectory(forRepo repo: RepositoryInfo) throws -> URL {
        let settings = try settings(forRepoId: repo.id) ?? PlanRepoSettings(repoId: repo.id)
        return settings.resolvedProposedDirectory(repoPath: repo.path)
    }

    func resolvedCompletedDirectory(forRepo repo: RepositoryInfo) throws -> URL {
        let settings = try settings(forRepoId: repo.id) ?? PlanRepoSettings(repoId: repo.id)
        return settings.resolvedCompletedDirectory(repoPath: repo.path)
    }
}
