import Foundation
import os

public struct MigrateDataPathsUseCase {
    private static let logger = Logger(subsystem: "com.aidevtools", category: "Migration")

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
        try migrateSettingsFile(name: "eval-settings.json", to: .evalSettings)
        try migrateSettingsFile(name: "plan-settings.json", to: .planSettings)
        try migrateArchitecturePlannerData()
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
