import Foundation
import UseCaseSDK
#if canImport(os)
import os
#endif

public struct MigrateDataPathsUseCase: UseCase {
    #if canImport(os)
    private static let logger = Logger(subsystem: "com.aidevtools", category: "Migration")
    #else
    private struct NoOpLogger {
        func info(_ message: String) {}
    }
    private static let logger = NoOpLogger()
    #endif

    private let dataPathsService: DataPathsService
    private let oldArchPlannerRoot: URL
    private let fileManager: FileManager

    public init(
        dataPathsService: DataPathsService,
        oldArchPlannerRoot: URL = URL.homeDirectory.appending(path: ".ai-dev-tools"),
        fileManager: FileManager = .default
    ) {
        self.dataPathsService = dataPathsService
        self.oldArchPlannerRoot = oldArchPlannerRoot
        self.fileManager = fileManager
    }

    public func run() throws {
        try migrateSettingsFile(name: "repositories.json", to: .repositories)
        try migrateArchitecturePlannerData()
        try migrateFeatureSettingsIntoRepositories()
        try migrateAnthropicSessions()
        try migrateDirectoryLayouts()
    }

    private func migrateSettingsFile(name: String, to servicePath: ServicePath) throws {
        let oldFile = dataPathsService.rootPath.appending(path: name)
        guard fileManager.fileExists(atPath: oldFile.path) else { return }

        let newDir = try dataPathsService.path(for: servicePath)
        let newFile = newDir.appending(path: name)

        guard !fileManager.fileExists(atPath: newFile.path) else {
            Self.logger.info("Skipping \(name): already exists at new location")
            return
        }

        try fileManager.copyItem(at: oldFile, to: newFile)
        Self.logger.info("Migrated \(name) to \(newFile.path)")
    }

    private func migrateFeatureSettingsIntoRepositories() throws {
        let repositoriesFile = dataPathsService.rootPath
            .appending(path: "repositories")
            .appending(path: "repositories.json")
        guard fileManager.fileExists(atPath: repositoriesFile.path) else { return }

        guard let repositoriesData = fileManager.contents(atPath: repositoriesFile.path),
              var repos = try JSONSerialization.jsonObject(with: repositoriesData) as? [[String: Any]] else {
            return
        }

        var indexByRepoId: [String: Int] = [:]
        for (i, repo) in repos.enumerated() {
            if let id = repo["id"] as? String {
                indexByRepoId[id] = i
            }
        }

        var didChange = false

        let prradarFile = dataPathsService.rootPath
            .appending(path: "prradar/settings/prradar-settings.json")
        if fileManager.fileExists(atPath: prradarFile.path),
           let data = fileManager.contents(atPath: prradarFile.path),
           let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for var entry in entries {
                guard let repoIdString = entry["repoId"] as? String,
                      let index = indexByRepoId[repoIdString] else { continue }
                entry.removeValue(forKey: "repoId")
                repos[index]["prradar"] = entry
                didChange = true
            }
            try fileManager.removeItem(at: prradarFile)
            Self.logger.info("Migrated prradar settings into repositories.json")
        }

        let evalFile = dataPathsService.rootPath
            .appending(path: "eval/settings/eval-settings.json")
        if fileManager.fileExists(atPath: evalFile.path),
           let data = fileManager.contents(atPath: evalFile.path),
           let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for var entry in entries {
                guard let repoIdString = entry["repoId"] as? String,
                      let index = indexByRepoId[repoIdString] else { continue }
                entry.removeValue(forKey: "repoId")
                repos[index]["eval"] = entry
                didChange = true
            }
            try fileManager.removeItem(at: evalFile)
            Self.logger.info("Migrated eval settings into repositories.json")
        }

        let planFile = dataPathsService.rootPath
            .appending(path: "plan/settings/plan-settings.json")
        if fileManager.fileExists(atPath: planFile.path),
           let data = fileManager.contents(atPath: planFile.path),
           let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for var entry in entries {
                guard let repoIdString = entry["repoId"] as? String,
                      let index = indexByRepoId[repoIdString] else { continue }
                entry.removeValue(forKey: "repoId")
                repos[index]["planner"] = entry
                didChange = true
            }
            try fileManager.removeItem(at: planFile)
            Self.logger.info("Migrated plan settings into repositories.json")
        }

        guard didChange else { return }

        let updatedData = try JSONSerialization.data(withJSONObject: repos, options: [.prettyPrinted, .sortedKeys])
        try updatedData.write(to: repositoriesFile, options: .atomic)
        Self.logger.info("Wrote merged repositories.json")
    }

    private func migrateAnthropicSessions() throws {
        let oldSessions = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".aidevtools/anthropic/sessions")
        guard fileManager.fileExists(atPath: oldSessions.path) else { return }

        let newSessions = dataPathsService.rootPath.appending(path: ServicePath.anthropicSessions.relativePath)
        guard !fileManager.fileExists(atPath: newSessions.path) else {
            Self.logger.info("Skipping anthropic sessions migration: already exists at new location")
            return
        }

        try fileManager.createDirectory(at: newSessions.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: oldSessions, to: newSessions)
        Self.logger.info("Migrated anthropic sessions to \(newSessions.path)")
    }

    private func migrateDirectoryLayouts() throws {
        let root = dataPathsService.rootPath

        let simpleMovements: [(String, String)] = [
            ("architecture-planner", "services/architecture-planner"),
            ("claude-chain", "services/claude-chain"),
            ("github", "services/github"),
            ("plan", "services/plan"),
            ("prradar", "services/pr-radar"),
            ("repos", "services/evals"),
            ("repositories", "services/repositories"),
        ]
        for (oldRelative, newRelative) in simpleMovements {
            try moveDirectory(from: root.appending(path: oldRelative), to: root.appending(path: newRelative))
        }

        try mergeApplicationSupportGitHub()
        try migrateRootLevelRepoDirs()

        let staleDirectories = ["eval", "logs", "worktrees"]
        for dirName in staleDirectories {
            let staleDir = root.appending(path: dirName)
            guard fileManager.fileExists(atPath: staleDir.path) else { continue }
            try fileManager.removeItem(at: staleDir)
            Self.logger.info("Deleted stale directory: \(staleDir.path)")
        }
    }

    private func moveDirectory(from source: URL, to destination: URL) throws {
        guard fileManager.fileExists(atPath: source.path) else { return }
        guard !fileManager.fileExists(atPath: destination.path) else {
            Self.logger.info("Skipping move of \(source.lastPathComponent): already exists at destination")
            return
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: source, to: destination)
        Self.logger.info("Moved \(source.path) → \(destination.path)")
    }

    private func mergeApplicationSupportGitHub() throws {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let source = appSupport.appending(path: "AIDevTools/github")
        guard fileManager.fileExists(atPath: source.path) else { return }

        let destination = dataPathsService.rootPath.appending(path: "services/github")

        if !fileManager.fileExists(atPath: destination.path) {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: source, to: destination)
            Self.logger.info("Moved Application Support github to \(destination.path)")
            return
        }

        let contents = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for item in contents {
            let dest = destination.appending(path: item.lastPathComponent)
            guard !fileManager.fileExists(atPath: dest.path) else {
                Self.logger.info("Skipping github/\(item.lastPathComponent): already at destination")
                continue
            }
            try fileManager.moveItem(at: item, to: dest)
            Self.logger.info("Merged github/\(item.lastPathComponent) from Application Support")
        }

        let remaining = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        if remaining.isEmpty {
            try fileManager.removeItem(at: source)
        }
    }

    private func migrateRootLevelRepoDirs() throws {
        let repoNames = try knownRepoNames()
        guard !repoNames.isEmpty else { return }

        let root = dataPathsService.rootPath
        for repoName in repoNames {
            let source = root.appending(path: repoName)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            let destination = root.appending(path: "services/evals/\(repoName)")
            try moveDirectory(from: source, to: destination)
        }
    }

    private func knownRepoNames() throws -> [String] {
        let candidates = [
            dataPathsService.rootPath.appending(path: "services/repositories/repositories.json"),
            dataPathsService.rootPath.appending(path: "repositories/repositories.json"),
        ]
        for file in candidates {
            guard fileManager.fileExists(atPath: file.path),
                  let data = fileManager.contents(atPath: file.path),
                  let repos = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                continue
            }
            return repos.compactMap { $0["name"] as? String }
        }
        return []
    }

    private func migrateArchitecturePlannerData() throws {
        guard fileManager.fileExists(atPath: oldArchPlannerRoot.path) else { return }

        let contents = try fileManager.contentsOfDirectory(
            at: oldArchPlannerRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        for repoDir in contents {
            let values = try repoDir.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }

            let repoName = repoDir.lastPathComponent
            let oldArchDir = repoDir.appending(path: "architecture-planner")
            guard fileManager.fileExists(atPath: oldArchDir.path) else { continue }

            let newArchDir = try dataPathsService.path(for: "architecture-planner", subdirectory: repoName)

            let archContents = try fileManager.contentsOfDirectory(
                at: oldArchDir,
                includingPropertiesForKeys: nil
            )
            for item in archContents {
                let dest = newArchDir.appending(path: item.lastPathComponent)
                guard !fileManager.fileExists(atPath: dest.path) else {
                    Self.logger.info("Skipping \(item.lastPathComponent) for \(repoName): already exists")
                    continue
                }
                try fileManager.copyItem(at: item, to: dest)
                Self.logger.info("Migrated architecture-planner/\(item.lastPathComponent) for \(repoName)")
            }
        }
    }
}
