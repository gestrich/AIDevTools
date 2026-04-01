import Foundation
import MarkdownPlannerService
import RepositorySDK

extension MarkdownPlannerRepoSettingsStore {
    func resolvedProposedDirectory(forRepo repo: RepositoryConfiguration) throws -> URL {
        let settings = try settings(forRepoId: repo.id) ?? MarkdownPlannerRepoSettings(repoId: repo.id)
        return settings.resolvedProposedDirectory(repoPath: repo.path)
    }

    func resolvedCompletedDirectory(forRepo repo: RepositoryConfiguration) throws -> URL {
        let settings = try settings(forRepoId: repo.id) ?? MarkdownPlannerRepoSettings(repoId: repo.id)
        return settings.resolvedCompletedDirectory(repoPath: repo.path)
    }
}
