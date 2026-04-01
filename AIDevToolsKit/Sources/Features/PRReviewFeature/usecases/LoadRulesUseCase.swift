import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import RepositorySDK
import UseCaseSDK

public struct LoadRulesUseCase: UseCase {

    private let config: PRRadarRepoConfig

    public init(config: PRRadarRepoConfig) {
        self.config = config
    }

    public func execute() async throws -> [(rulePath: RulePath, rules: [ReviewRule])] {
        let gitOps = GitHubServiceFactory.createGitOps()
        let ruleLoader = RuleLoaderService(gitOps: gitOps)
        var result: [(rulePath: RulePath, rules: [ReviewRule])] = []
        for rulePath in config.rulePaths {
            let dir = config.resolvedRulesDir(for: rulePath)
            let rules = try await ruleLoader.loadAllRules(rulesDir: dir)
            result.append((rulePath: rulePath, rules: rules))
        }
        return result
    }
}
