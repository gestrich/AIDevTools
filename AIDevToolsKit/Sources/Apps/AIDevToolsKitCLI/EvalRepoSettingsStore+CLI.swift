import EvalService
import Foundation
import RepositorySDK

extension EvalRepoSettingsStore {
    func casesDirectory(forRepo repo: RepositoryConfiguration) throws -> URL {
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
