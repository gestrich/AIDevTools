import Foundation

public struct EvalRepoSettings: Codable, Sendable {
    public let repoId: UUID
    public var casesDirectory: String

    public init(repoId: UUID, casesDirectory: String) {
        self.repoId = repoId
        self.casesDirectory = casesDirectory
    }

    public func resolvedCasesDirectory(repoPath: URL) -> URL {
        let expanded = NSString(string: casesDirectory).expandingTildeInPath
        if NSString(string: expanded).isAbsolutePath {
            return URL(filePath: expanded)
        }
        let resolved = repoPath.path(percentEncoded: false) + "/" + expanded
        return URL(filePath: resolved)
    }
}
