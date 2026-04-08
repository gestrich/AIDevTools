import CredentialService
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import UseCaseSDK

public struct PostSingleCommentUseCase: UseCase {

    private let config: PRRadarRepoConfig

    public init(config: PRRadarRepoConfig) {
        self.config = config
    }

    public func execute(
        comment: PRComment,
        suppressedCount: Int = 0,
        commitSHA: String,
        prNumber: Int
    ) async throws -> Bool {
        guard let githubAccount = config.githubAccount else {
            throw CredentialError.notConfigured(account: config.name)
        }
        let (gitHub, _) = try await GitHubServiceFactory.create(repoPath: config.repoPath, githubAccount: githubAccount, explicitToken: config.explicitToken)
        let commentService = CommentService(githubService: gitHub)

        do {
            try await commentService.postReviewComment(
                prNumber: prNumber,
                comment: comment,
                suppressedCount: suppressedCount,
                commitSHA: commitSHA
            )
            return true
        } catch {
            return false
        }
    }
}
