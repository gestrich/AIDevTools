import Foundation
import MarkdownPlannerService
import RepositorySDK

extension MarkdownPlannerRepoSettingsStore {
    func resolvedProposedDirectory(forRepo repo: RepositoryConfiguration) -> URL {
        let settings = repo.planner ?? MarkdownPlannerRepoSettings()
        return settings.resolvedProposedDirectory(repoPath: repo.path)
    }

    func resolvedCompletedDirectory(forRepo repo: RepositoryConfiguration) -> URL {
        let settings = repo.planner ?? MarkdownPlannerRepoSettings()
        return settings.resolvedCompletedDirectory(repoPath: repo.path)
    }
}
