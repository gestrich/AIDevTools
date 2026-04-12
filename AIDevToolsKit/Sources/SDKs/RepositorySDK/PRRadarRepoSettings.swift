import Foundation

public struct PRRadarRepoSettings: Codable, Sendable {
    public var rulePaths: [RulePath]
    public var diffSource: DiffSource

    public init(rulePaths: [RulePath] = [], diffSource: DiffSource = .git) {
        self.rulePaths = rulePaths
        self.diffSource = diffSource
    }
}
