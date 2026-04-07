import AIOutputSDK
import ClaudeChainService
import Foundation
import GitSDK
import SweepFeature
import UseCaseSDK

public struct ExecuteSweepChainUseCase: UseCase {

    public struct Options: Sendable {
        public let baseBranch: String
        public let githubAccount: String?
        public let project: ChainProject
        public let repoPath: URL
        public let worktreesDirectory: URL?

        public init(project: ChainProject, repoPath: URL, githubAccount: String? = nil, worktreesDirectory: URL? = nil) {
            self.baseBranch = project.baseBranch
            self.githubAccount = githubAccount
            self.project = project
            self.repoPath = repoPath
            self.worktreesDirectory = worktreesDirectory
        }
    }

    public typealias Progress = RunSweepBatchUseCase.Progress

    private let client: any AIClient
    private let git: GitClient

    public init(client: any AIClient, git: GitClient = GitClient()) {
        self.client = client
        self.git = git
    }

    public func run(
        options: Options,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> ExecuteSpecChainUseCase.Result {
        let taskDirectory = options.repoPath.appendingPathComponent(options.project.basePath)
        let useCase = RunSweepBatchUseCase(client: client, git: git)
        let sweepOptions = RunSweepBatchUseCase.Options(
            taskDirectory: taskDirectory,
            taskRelativePath: options.project.basePath,
            repoPath: options.repoPath,
            baseBranch: options.baseBranch,
            worktreesDirectory: options.worktreesDirectory
        )

        let result = try await useCase.run(options: sweepOptions, onProgress: onProgress)
        return ExecuteSpecChainUseCase.Result(
            success: result.success,
            message: result.message,
            prURL: result.prURL
        )
    }
}
