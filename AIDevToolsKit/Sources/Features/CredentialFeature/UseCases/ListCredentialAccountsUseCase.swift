import Foundation
import CredentialService
import UseCaseSDK

public struct ListCredentialAccountsUseCase: UseCase {

    private let settingsService: CredentialSettingsService

    public init(settingsService: CredentialSettingsService) {
        self.settingsService = settingsService
    }

    public func execute() throws -> [String] {
        try settingsService.listCredentialAccounts()
    }
}
