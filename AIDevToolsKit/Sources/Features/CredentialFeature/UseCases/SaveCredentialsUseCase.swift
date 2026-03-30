import Foundation
import CredentialService
import UseCaseSDK

public struct SaveCredentialsUseCase: UseCase {

    private let settingsService: CredentialSettingsService

    public init(settingsService: CredentialSettingsService) {
        self.settingsService = settingsService
    }

    @discardableResult
    public func execute(
        account: String,
        gitHubAuth: GitHubAuth?,
        anthropicKey: String?
    ) throws -> [CredentialStatus] {
        if let gitHubAuth {
            try settingsService.saveGitHubAuth(gitHubAuth, account: account)
        }
        if let anthropicKey, !anthropicKey.isEmpty {
            try settingsService.saveAnthropicKey(anthropicKey, account: account)
        }
        return try CredentialStatusLoader(settingsService: settingsService).loadAllStatuses()
    }
}
