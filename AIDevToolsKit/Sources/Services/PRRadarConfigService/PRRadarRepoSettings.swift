import Foundation

public struct PRRadarRepoSettings: Codable, Sendable {
    public let repoId: UUID
    public var rulePaths: [RulePath]
    public var diffSource: DiffSource
    public var agentScriptPath: String

    public init(repoId: UUID, rulePaths: [RulePath] = [], diffSource: DiffSource = .git, agentScriptPath: String = "") {
        self.repoId = repoId
        self.rulePaths = rulePaths
        self.diffSource = diffSource
        self.agentScriptPath = agentScriptPath
    }
}
