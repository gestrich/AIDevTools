import Foundation

public struct MarkdownPlannerRepoSettingsStore: Sendable {
    private let filePath: URL

    public init(filePath: URL) {
        self.filePath = filePath
    }

    public func loadAll() throws -> [MarkdownPlannerRepoSettings] {
        guard FileManager.default.fileExists(atPath: filePath.path()) else {
            return []
        }
        let data = try Data(contentsOf: filePath)
        return try JSONDecoder().decode([MarkdownPlannerRepoSettings].self, from: data)
    }

    public func save(_ settings: [MarkdownPlannerRepoSettings]) throws {
        try ensureDirectoryExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: filePath, options: .atomic)
    }

    public func settings(forRepoId repoId: UUID) throws -> MarkdownPlannerRepoSettings? {
        try loadAll().first { $0.repoId == repoId }
    }

    public enum UpdateError: Error, LocalizedError {
        case emptyDirectory(String)

        public var errorDescription: String? {
            switch self {
            case .emptyDirectory(let field):
                return "\(field) cannot be an empty string; pass nil to use the default"
            }
        }
    }

    public func update(repoId: UUID, proposedDirectory: String?, completedDirectory: String?) throws {
        guard proposedDirectory?.isEmpty != true else {
            throw UpdateError.emptyDirectory("proposedDirectory")
        }
        guard completedDirectory?.isEmpty != true else {
            throw UpdateError.emptyDirectory("completedDirectory")
        }
        var all = try loadAll()
        if let index = all.firstIndex(where: { $0.repoId == repoId }) {
            all[index].proposedDirectory = proposedDirectory
            all[index].completedDirectory = completedDirectory
        } else {
            all.append(MarkdownPlannerRepoSettings(
                repoId: repoId,
                proposedDirectory: proposedDirectory,
                completedDirectory: completedDirectory
            ))
        }
        try save(all)
    }

    public func remove(repoId: UUID) throws {
        var all = try loadAll()
        all.removeAll { $0.repoId == repoId }
        try save(all)
    }

    private func ensureDirectoryExists() throws {
        let directory = filePath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
