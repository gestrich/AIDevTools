import AIOutputSDK
import ClaudeChainSDK
import ClaudeChainService
import CredentialService
import Foundation

public struct ExecuteChainUseCase: Sendable {

    public struct Options: Sendable {
        public let githubAccount: String?
        public let projectName: String
        public let repoPath: URL

        public init(repoPath: URL, projectName: String, githubAccount: String? = nil) {
            self.githubAccount = githubAccount
            self.projectName = projectName
            self.repoPath = repoPath
        }
    }

    public struct Result: Sendable {
        public let message: String
        public let phasesCompleted: Int
        public let prNumber: String?
        public let prURL: String?
        public let success: Bool
        public let taskDescription: String?

        public init(
            success: Bool,
            message: String,
            prURL: String? = nil,
            prNumber: String? = nil,
            taskDescription: String? = nil,
            phasesCompleted: Int = 0
        ) {
            self.message = message
            self.phasesCompleted = phasesCompleted
            self.prNumber = prNumber
            self.prURL = prURL
            self.success = success
            self.taskDescription = taskDescription
        }
    }

    public typealias Progress = RunChainTaskUseCase.Progress

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
                settingsService: CredentialSettingsService(),
                githubAccount: githubAccount
            )
            if case .token(let token) = resolver.getGitHubAuth() {
                setenv("GH_TOKEN", token, 1)
            }
        }

        let innerOptions = RunChainTaskUseCase.Options(
            repoPath: options.repoPath,
            projectName: options.projectName
        )

        let useCase = RunChainTaskUseCase(client: client)
        let innerResult = try await useCase.run(options: innerOptions, onProgress: onProgress)

        return Result(
            success: innerResult.success,
            message: innerResult.message,
            prURL: innerResult.prURL,
            prNumber: innerResult.prNumber,
            taskDescription: innerResult.taskDescription,
            phasesCompleted: innerResult.phasesCompleted
        )
    }
}
