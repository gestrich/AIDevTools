import Foundation

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
