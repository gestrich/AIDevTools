import Foundation
import MarkdownPlannerService
import RepositorySDK

extension MarkdownPlannerRepoSettingsStore {
    func resolvedProposedDirectory(forRepo repo: RepositoryInfo) throws -> URL {
        let settings = try settings(forRepoId: repo.id) ?? MarkdownPlannerRepoSettings(repoId: repo.id)
        return settings.resolvedProposedDirectory(repoPath: repo.path)
    }

    func resolvedCompletedDirectory(forRepo repo: RepositoryInfo) throws -> URL {
        let settings = try settings(forRepoId: repo.id) ?? MarkdownPlannerRepoSettings(repoId: repo.id)
        return settings.resolvedCompletedDirectory(repoPath: repo.path)
    }
}
