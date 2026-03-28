import Foundation

public struct MarkdownPlannerRepoSettings: Codable, Sendable {
    public static let defaultProposedDirectory = "docs/proposed"
    public static let defaultCompletedDirectory = "docs/completed"

    public let repoId: UUID
    public var completedDirectory: String?
    public var proposedDirectory: String?

    public init(repoId: UUID, proposedDirectory: String? = nil, completedDirectory: String? = nil) {
        self.repoId = repoId
        self.completedDirectory = completedDirectory
        self.proposedDirectory = proposedDirectory
    }

    public func resolvedProposedDirectory(repoPath: URL) -> URL {
        resolve(directory: proposedDirectory ?? Self.defaultProposedDirectory, repoPath: repoPath)
    }

    public func resolvedCompletedDirectory(repoPath: URL) -> URL {
        resolve(directory: completedDirectory ?? Self.defaultCompletedDirectory, repoPath: repoPath)
    }

    // MARK: - Private

    private func resolve(directory: String, repoPath: URL) -> URL {
        let expanded = NSString(string: directory).expandingTildeInPath
        if NSString(string: expanded).isAbsolutePath {
            return URL(filePath: expanded)
        }
        let resolved = repoPath.path(percentEncoded: false) + "/" + expanded
        return URL(filePath: resolved)
    }
}
