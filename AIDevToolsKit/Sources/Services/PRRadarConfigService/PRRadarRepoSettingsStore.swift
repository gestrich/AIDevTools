import Foundation

public struct PRRadarRepoSettingsStore: Sendable {
    private let filePath: URL

    public init(filePath: URL) {
        self.filePath = filePath
    }

    public func loadAll() throws -> [PRRadarRepoSettings] {
        guard FileManager.default.fileExists(atPath: filePath.path()) else {
            return []
        }
        let data = try Data(contentsOf: filePath)
        return try JSONDecoder().decode([PRRadarRepoSettings].self, from: data)
    }

    public func save(_ settings: [PRRadarRepoSettings]) throws {
        try ensureDirectoryExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: filePath, options: .atomic)
    }

    public func settings(forRepoId repoId: UUID) throws -> PRRadarRepoSettings? {
        try loadAll().first { $0.repoId == repoId }
    }

    public func update(repoId: UUID, rulePaths: [RulePath], diffSource: DiffSource, agentScriptPath: String = "") throws {
        var all = try loadAll()
        if let index = all.firstIndex(where: { $0.repoId == repoId }) {
            all[index].rulePaths = rulePaths
            all[index].diffSource = diffSource
            all[index].agentScriptPath = agentScriptPath
        } else {
            all.append(PRRadarRepoSettings(repoId: repoId, rulePaths: rulePaths, diffSource: diffSource, agentScriptPath: agentScriptPath))
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
