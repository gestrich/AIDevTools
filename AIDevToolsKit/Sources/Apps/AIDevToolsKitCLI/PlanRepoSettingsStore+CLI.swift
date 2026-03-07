import Foundation
import PlanRunnerService
import RepositorySDK

extension PlanRepoSettingsStore {
    static func fromCLI(dataPath: String?) -> PlanRepoSettingsStore {
        let path: URL
        if let dataPath {
            path = URL(filePath: dataPath)
        } else {
            path = RepositoryStoreConfiguration().dataPath
        }
        return PlanRepoSettingsStore(dataPath: path)
    }

    func resolvedProposedDirectory(forRepo repo: RepositoryInfo) -> URL {
        let settings = try? settings(forRepoId: repo.id)
        let effective = settings ?? PlanRepoSettings(repoId: repo.id)
        return effective.resolvedProposedDirectory(repoPath: repo.path)
    }

    func resolvedCompletedDirectory(forRepo repo: RepositoryInfo) -> URL {
        let settings = try? settings(forRepoId: repo.id)
        let effective = settings ?? PlanRepoSettings(repoId: repo.id)
        return effective.resolvedCompletedDirectory(repoPath: repo.path)
    }
}
