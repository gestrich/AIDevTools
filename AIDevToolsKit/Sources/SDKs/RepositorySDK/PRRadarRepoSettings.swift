import Foundation

public struct PRRadarRepoSettings: Codable, Sendable {
    public var rulePaths: [RulePath]
    public var diffSource: DiffSource
    public var agentScriptPath: String

    public init(rulePaths: [RulePath] = [], diffSource: DiffSource = .git, agentScriptPath: String = "") {
        self.rulePaths = rulePaths
        self.diffSource = diffSource
        self.agentScriptPath = agentScriptPath
    }
}
