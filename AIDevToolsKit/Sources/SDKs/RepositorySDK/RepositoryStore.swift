import Foundation

public struct RepositoryStore: Sendable {
    private let filePath: URL

    public init(repositoriesFile: URL) {
        self.filePath = repositoriesFile
    }

    public func loadAll() throws -> [RepositoryConfiguration] {
        guard FileManager.default.fileExists(atPath: filePath.path()) else {
            return []
        }
        let data = try Data(contentsOf: filePath)
        return try JSONDecoder().decode([RepositoryConfiguration].self, from: data)
    }

    public func save(_ repositories: [RepositoryConfiguration]) throws {
        try ensureDirectoryExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(repositories)
        try data.write(to: filePath, options: .atomic)
    }

    public func add(_ repository: RepositoryConfiguration) throws {
        var all = try loadAll()
        all.append(repository)
        try save(all)
    }

    public func update(_ repository: RepositoryConfiguration) throws {
        var all = try loadAll()
        guard let index = all.firstIndex(where: { $0.id == repository.id }) else {
            return
        }
        all[index] = repository
        try save(all)
    }

    public func remove(id: UUID) throws {
        var all = try loadAll()
        all.removeAll { $0.id == id }
        try save(all)
    }

    public func find(byID id: UUID) throws -> RepositoryConfiguration? {
        try loadAll().first { $0.id == id }
    }

    public func find(byPath path: URL) throws -> RepositoryConfiguration? {
        try loadAll().first { $0.path == path }
    }

    private func ensureDirectoryExists() throws {
        let directory = filePath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
