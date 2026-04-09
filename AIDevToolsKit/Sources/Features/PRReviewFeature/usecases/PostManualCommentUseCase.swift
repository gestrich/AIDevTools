import CredentialService
import PRRadarCLIService
import PRRadarConfigService
import UseCaseSDK

public struct PostManualCommentUseCase: UseCase {

    private let config: PRRadarRepoConfig

    public init(config: PRRadarRepoConfig) {
        self.config = config
    }

    public func execute(
        prNumber: Int,
        filePath: String,
        lineNumber: Int,
        body: String,
        commitSHA: String
    ) async throws -> Bool {
        guard let githubAccount = config.githubAccount else {
            throw CredentialError.notConfigured(account: config.name)
        }
        let gitHub = try await GitHubServiceFactory.createGitHubAPI(repoPath: config.repoPath, githubAccount: githubAccount, explicitToken: config.explicitToken)
        try await gitHub.postReviewComment(
            number: prNumber,
            commitId: commitSHA,
            path: filePath,
            line: lineNumber,
            body: body
        )
        return true
    }
}
