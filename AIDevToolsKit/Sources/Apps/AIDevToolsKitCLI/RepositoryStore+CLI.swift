import Foundation
import RepositorySDK

extension RepositoryStore {
    static func cliDataPath(from option: String?) -> URL {
        if let option {
            URL(filePath: option)
        } else {
            URL.homeDirectory.appending(path: "Desktop/ai-dev-tools")
        }
    }

    static func fromCLI(dataPath: String?) -> RepositoryStore {
        let resolvedPath = cliDataPath(from: dataPath)
        return RepositoryStore(repositoriesFile: resolvedPath.appending(path: "repositories.json"))
    }

    func repoConfig(forRepoAt repoPath: URL) throws -> RepositoryInfo {
        let repos = try loadAll()
        guard let repoConfig = repos.first(where: { $0.path.standardized.path == repoPath.standardized.path }) else {
            throw RepositoryStoreError.repositoryNotFound(repoPath)
        }
        return repoConfig
    }

    func outputDirectory(forRepoAt repoPath: URL, dataPath: URL) throws -> URL {
        let repo = try repoConfig(forRepoAt: repoPath)
        return dataPath.appendingPathComponent(repo.name)
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
