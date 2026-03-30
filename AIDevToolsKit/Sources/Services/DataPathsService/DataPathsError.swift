import Foundation

public enum DataPathsError: Error, LocalizedError {
    case directoryCreationFailed(String, Error)
    case invalidPath(String)
    case invalidServiceName(String)

    public var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let path, let error):
            return "Failed to create directory at \(path): \(error.localizedDescription)"
        case .invalidPath(let path):
            return "Invalid data path: \(path)"
        case .invalidServiceName(let name):
            return "Invalid service name: \(name)"
        }
    }
}
