import Foundation
import RepositorySDK

extension RepositoryStore {
    static func fromCLI(dataPath: String?) -> RepositoryStore {
        let config: RepositoryStoreConfiguration
        let resolvedPath = if let dataPath {
            URL(filePath: dataPath)
        } else {
            URL.homeDirectory.appending(path: "Desktop/ai-dev-tools")
        }
        config = RepositoryStoreConfiguration(dataPath: resolvedPath)
        return RepositoryStore(configuration: config)
    }

    func repoConfig(forRepoAt repoPath: URL) throws -> RepositoryInfo {
        let repos = try loadAll()
        guard let repoConfig = repos.first(where: { $0.path.standardized.path == repoPath.standardized.path }) else {
            throw RepositoryStoreError.repositoryNotFound(repoPath)
        }
        return repoConfig
    }

    func outputDirectory(forRepoAt repoPath: URL) throws -> URL {
        let repo = try repoConfig(forRepoAt: repoPath)
        return outputDirectory(for: repo)
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
