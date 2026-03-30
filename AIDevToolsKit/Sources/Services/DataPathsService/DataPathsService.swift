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

public enum ServicePath {
    case architecturePlanner
    case evalSettings
    case github(repoSlug: String)
    case planSettings
    case prradarOutput(String)
    case prradarSettings
    case repoOutput(String)
    case repositories

    var relativePath: String {
        switch self {
        case .architecturePlanner:
            return "architecture-planner"
        case .evalSettings:
            return "eval/settings"
        case .github(let repoSlug):
            return "github/\(repoSlug)"
        case .planSettings:
            return "plan/settings"
        case .prradarOutput(let repoName):
            return "prradar/repos/\(repoName)"
        case .prradarSettings:
            return "prradar/settings"
        case .repoOutput(let repoName):
            return "repos/\(repoName)"
        case .repositories:
            return "repositories"
        }
    }
}

public final class DataPathsService: @unchecked Sendable {
    public let rootPath: URL
    private let fileManager: FileManager

    public init(rootPath: URL) throws {
        self.rootPath = rootPath
        self.fileManager = FileManager.default

        try Self.createDirectoryIfNeeded(at: rootPath, fileManager: fileManager)
    }

    internal init(rootPath: URL, fileManager: FileManager) throws {
        self.rootPath = rootPath
        self.fileManager = fileManager

        try Self.createDirectoryIfNeeded(at: rootPath, fileManager: fileManager)
    }

    public func path(for servicePath: ServicePath) throws -> URL {
        let resolvedPath = rootPath.appendingPathComponent(servicePath.relativePath)
        try Self.createDirectoryIfNeeded(at: resolvedPath, fileManager: fileManager)
        return resolvedPath
    }

    public func path(for service: String) throws -> URL {
        guard !service.isEmpty else {
            throw DataPathsError.invalidServiceName("Service name cannot be empty")
        }

        let servicePath = rootPath.appendingPathComponent(service)
        try Self.createDirectoryIfNeeded(at: servicePath, fileManager: fileManager)
        return servicePath
    }

    public func path(for service: String, subdirectory: String) throws -> URL {
        guard !subdirectory.isEmpty else {
            throw DataPathsError.invalidServiceName("Subdirectory name cannot be empty")
        }

        let servicePath = try path(for: service)
        let subdirectoryPath = servicePath.appendingPathComponent(subdirectory)
        try Self.createDirectoryIfNeeded(at: subdirectoryPath, fileManager: fileManager)
        return subdirectoryPath
    }

    private static func createDirectoryIfNeeded(at path: URL, fileManager: FileManager) throws {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory)

        if exists && !isDirectory.boolValue {
            throw DataPathsError.invalidPath("Path exists but is not a directory: \(path.path)")
        }

        if !exists {
            do {
                try fileManager.createDirectory(at: path, withIntermediateDirectories: true)
            } catch {
                throw DataPathsError.directoryCreationFailed(path.path, error)
            }
        }
    }
}
