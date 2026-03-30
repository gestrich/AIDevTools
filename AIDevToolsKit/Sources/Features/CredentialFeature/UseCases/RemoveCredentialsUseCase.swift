import Foundation
import CredentialService
import UseCaseSDK

public struct RemoveCredentialsUseCase: UseCase {

    private let settingsService: CredentialSettingsService

    public init(settingsService: CredentialSettingsService) {
        self.settingsService = settingsService
    }

    @discardableResult
    public func execute(account: String) throws -> [CredentialStatus] {
        try settingsService.removeCredentials(account: account)
        return try CredentialStatusLoader(settingsService: settingsService).loadAllStatuses()
    }
}
