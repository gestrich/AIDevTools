import EvalService
import Foundation
import RepositorySDK

extension EvalRepoSettingsStore {
    static func fromCLI(dataPath: String?) -> EvalRepoSettingsStore {
        let path: URL
        if let dataPath {
            path = URL(filePath: dataPath)
        } else {
            path = URL.homeDirectory.appending(path: "Desktop/ai-dev-tools")
        }
        return EvalRepoSettingsStore(dataPath: path)
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
