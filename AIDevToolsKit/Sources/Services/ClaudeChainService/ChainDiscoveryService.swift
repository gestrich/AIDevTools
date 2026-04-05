import Foundation
import GitSDK

/// Discovers `ClaudeChainSource` instances from a repository.
public protocol ChainDiscoveryService: Sendable {
    func discoverSources(repoPath: URL) throws -> [any ClaudeChainSource]
}

/// Scans the local filesystem for regular (`claude-chain/`) and sweep
/// (`claude-chain-sweep/`) chain directories.
public struct LocalChainDiscoveryService: ChainDiscoveryService {

    public init() {}

    public func discoverSources(repoPath: URL) throws -> [any ClaudeChainSource] {
        var sources: [any ClaudeChainSource] = []
        sources += discoverRegularSources(repoPath: repoPath)
        sources += discoverSweepSources(repoPath: repoPath)
        return sources
    }

    // MARK: - Private

    private func discoverRegularSources(repoPath: URL) -> [any ClaudeChainSource] {
        let chainDir = repoPath.appendingPathComponent(ClaudeChainConstants.projectDirectoryPrefix).path
        let projects = Project.findAll(baseDir: chainDir)
        return projects.map { project in
            MarkdownClaudeChainSource(projectName: project.name, repoPath: repoPath)
        }
    }

    private func discoverSweepSources(repoPath: URL) -> [any ClaudeChainSource] {
        let sweepDir = repoPath.appendingPathComponent(ClaudeChainConstants.sweepChainDirectory)
        guard FileManager.default.fileExists(atPath: sweepDir.path) else { return [] }

        let entries = (try? FileManager.default.contentsOfDirectory(atPath: sweepDir.path)) ?? []
        return entries.sorted().compactMap { entry -> (any ClaudeChainSource)? in
            let taskDir = sweepDir.appendingPathComponent(entry)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: taskDir.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  FileManager.default.fileExists(atPath: taskDir.appendingPathComponent("spec.md").path)
            else { return nil }
            return SweepClaudeChainSource(taskName: entry, taskDirectory: taskDir, repoPath: repoPath)
        }
    }
}
