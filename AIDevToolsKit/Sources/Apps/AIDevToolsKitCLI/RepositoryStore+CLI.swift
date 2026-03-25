import Foundation
import RepositorySDK

extension RepositoryStore {
    func repoConfig(forRepoAt repoPath: URL) throws -> RepositoryInfo {
        let repos = try loadAll()
        guard let repoConfig = repos.first(where: { $0.path.standardized.path == repoPath.standardized.path }) else {
            throw RepositoryStoreError.repositoryNotFound(repoPath)
        }
        return repoConfig
    }
}

enum RepositoryStoreError: LocalizedError {
    case repositoryNotFound(URL)

    var errorDescription: String? {
        switch self {
        case .repositoryNotFound(let url):
            return "Repository not found in config: \(url.path())"
        }
    }
}
