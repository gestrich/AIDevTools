import Foundation
import GitSDK

/// Discovers `ClaudeChainSource` instances from a repository.
public protocol ChainDiscoveryService: Sendable {
    func discoverSources(repoPath: URL) throws -> [any ClaudeChainSource]
}

/// Scans the local filesystem for regular (`claude-chain/`) and maintenance
/// (`claude-chain-maintenance/`) chain directories.
public struct LocalChainDiscoveryService: ChainDiscoveryService {

    public init() {}

    public func discoverSources(repoPath: URL) throws -> [any ClaudeChainSource] {
        var sources: [any ClaudeChainSource] = []
        sources += discoverRegularSources(repoPath: repoPath)
        return sources
    }

    // MARK: - Private

    private func discoverRegularSources(repoPath: URL) -> [any ClaudeChainSource] {
        let chainDir = repoPath.appendingPathComponent(ClaudeChainConstants.projectDirectoryPrefix).path
        let projects = Project.findAll(baseDir: chainDir)
        return projects.map { project in
            MarkdownClaudeChainSource(project: project, repoPath: repoPath)
        }
    }
}
