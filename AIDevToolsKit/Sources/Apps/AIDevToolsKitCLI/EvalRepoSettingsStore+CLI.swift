import EvalService
import Foundation
import RepositorySDK

extension EvalRepoSettingsStore {
    static func fromCLI(dataPath: String?) -> EvalRepoSettingsStore {
        let path = RepositoryStore.cliDataPath(from: dataPath)
        return EvalRepoSettingsStore(filePath: path.appending(path: "eval-settings.json"))
    }

    func casesDirectory(forRepo repo: RepositoryInfo) throws -> URL {
        guard let settings = try settings(forRepoId: repo.id) else {
            throw EvalRepoSettingsError.casesDirectoryNotConfigured(repo.name)
        }
        return settings.resolvedCasesDirectory(repoPath: repo.path)
    }
}

enum EvalRepoSettingsError: LocalizedError {
    case casesDirectoryNotConfigured(String)

    var errorDescription: String? {
        switch self {
        case .casesDirectoryNotConfigured(let name):
            return "No cases directory configured for repository: \(name)"
        }
    }
}
