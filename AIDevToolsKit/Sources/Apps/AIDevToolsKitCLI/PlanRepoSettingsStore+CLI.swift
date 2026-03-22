import Foundation
import PlanRunnerService
import RepositorySDK

extension PlanRepoSettingsStore {
    static func fromCLI(dataPath: String?) -> PlanRepoSettingsStore {
        let path: URL
        if let dataPath {
            path = URL(filePath: dataPath)
        } else {
            path = URL.homeDirectory.appending(path: "Desktop/ai-dev-tools")
        }
        return PlanRepoSettingsStore(dataPath: path)
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
