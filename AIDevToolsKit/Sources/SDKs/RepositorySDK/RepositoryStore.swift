import Foundation

public struct RepositoryStore: Sendable {
    private let filePath: URL

    public init(repositoriesFile: URL) {
        self.filePath = repositoriesFile
    }

    public func loadAll() throws -> [RepositoryInfo] {
        guard FileManager.default.fileExists(atPath: filePath.path()) else {
            return []
        }
        let data = try Data(contentsOf: filePath)
        return try JSONDecoder().decode([RepositoryInfo].self, from: data)
    }

    public func save(_ repositories: [RepositoryInfo]) throws {
        try ensureDirectoryExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(repositories)
        try data.write(to: filePath, options: .atomic)
    }

    public func add(_ repository: RepositoryInfo) throws {
        var all = try loadAll()
        all.append(repository)
        try save(all)
    }

    public func update(_ repository: RepositoryInfo) throws {
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

    public func find(byID id: UUID) throws -> RepositoryInfo? {
        try loadAll().first { $0.id == id }
    }

    public func find(byPath path: URL) throws -> RepositoryInfo? {
        try loadAll().first { $0.path == path }
    }

    private func ensureDirectoryExists() throws {
        let directory = filePath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
