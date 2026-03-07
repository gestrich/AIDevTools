import Foundation
import RepositorySDK

public struct AddRepositoryUseCase: Sendable {
    private let store: RepositoryStore

    public init(store: RepositoryStore) {
        self.store = store
    }

    public func run(path: URL, name: String? = nil) throws -> RepositoryInfo {
        guard FileManager.default.fileExists(atPath: path.path()) else {
            throw AddRepositoryError.directoryNotFound(path)
        }
        let repo = RepositoryInfo(path: path, name: name)
        try store.add(repo)
        return repo
    }
}

public enum AddRepositoryError: Error, LocalizedError {
    case directoryNotFound(URL)

    public var errorDescription: String? {
        switch self {
        case .directoryNotFound(let url):
            return "Directory does not exist: \(url.path())"
        }
    }
}
