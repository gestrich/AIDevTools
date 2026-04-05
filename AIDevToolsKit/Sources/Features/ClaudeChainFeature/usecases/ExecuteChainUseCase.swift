import AIOutputSDK
import ClaudeChainSDK
import ClaudeChainService
import CredentialService
import Foundation
import UseCaseSDK

public struct ExecuteMarkdownChainUseCase: UseCase {

    public struct Options: Sendable {
        public let baseBranch: String
        public let githubAccount: String?
        public let projectName: String
        public let repoPath: URL
        public let stagingOnly: Bool
        public let taskIndex: Int?

        public init(repoPath: URL, projectName: String, baseBranch: String, githubAccount: String? = nil, taskIndex: Int? = nil, stagingOnly: Bool = false) {
            self.baseBranch = baseBranch
            self.githubAccount = githubAccount
            self.projectName = projectName
            self.repoPath = repoPath
            self.stagingOnly = stagingOnly
            self.taskIndex = taskIndex
        }
    }

    public struct Result: Sendable {
        public let branchName: String?
        public let isStagingOnly: Bool
        public let message: String
        public let phasesCompleted: Int
        public let prNumber: String?
        public let prURL: String?
        public let success: Bool
        public let taskDescription: String?

        public init(
            success: Bool,
            message: String,
            branchName: String? = nil,
            isStagingOnly: Bool = false,
            prURL: String? = nil,
            prNumber: String? = nil,
            taskDescription: String? = nil,
            phasesCompleted: Int = 0
        ) {
            self.branchName = branchName
            self.isStagingOnly = isStagingOnly
            self.message = message
            self.phasesCompleted = phasesCompleted
            self.prNumber = prNumber
            self.prURL = prURL
            self.success = success
            self.taskDescription = taskDescription
        }
    }

    public typealias Progress = RunMarkdownChainTaskUseCase.Progress

    private let client: any AIClient

    public init(client: any AIClient) {
        self.client = client
    }

    public func run(
        options: Options,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> Result {
        // Resolve GH_TOKEN from credential system when a github account is configured
        if let githubAccount = options.githubAccount {
            let resolver = CredentialResolver(
                settingsService: SecureSettingsService(),
                githubAccount: githubAccount
            )
            if case .token(let token) = resolver.getGitHubAuth() {
                setenv("GH_TOKEN", token, 1)
            }
        }

        let innerOptions = RunMarkdownChainTaskUseCase.Options(
            repoPath: options.repoPath,
            projectName: options.projectName,
            baseBranch: options.baseBranch,
            taskIndex: options.taskIndex,
            stagingOnly: options.stagingOnly
        )

        let useCase = RunMarkdownChainTaskUseCase(client: client)
        let innerResult = try await useCase.run(options: innerOptions, onProgress: onProgress)

        return Result(
            success: innerResult.success,
            message: innerResult.message,
            branchName: innerResult.branchName,
            isStagingOnly: innerResult.isStagingOnly,
            prURL: innerResult.prURL,
            prNumber: innerResult.prNumber,
            taskDescription: innerResult.taskDescription,
            phasesCompleted: innerResult.phasesCompleted
        )
    }
}
