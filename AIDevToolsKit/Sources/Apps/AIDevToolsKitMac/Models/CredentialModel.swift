import CredentialFeature
import CredentialService
import Foundation

@MainActor @Observable
final class CredentialModel {

    private let listCredentialAccountsUseCase: ListCredentialAccountsUseCase
    private let loadCredentialStatusUseCase: LoadCredentialStatusUseCase
    private let removeCredentialsUseCase: RemoveCredentialsUseCase
    private let saveCredentialsUseCase: SaveCredentialsUseCase

    private(set) var credentialAccounts: [CredentialStatus] = []

    init(
        listCredentialAccountsUseCase: ListCredentialAccountsUseCase,
        loadCredentialStatusUseCase: LoadCredentialStatusUseCase,
        removeCredentialsUseCase: RemoveCredentialsUseCase,
        saveCredentialsUseCase: SaveCredentialsUseCase
    ) {
        self.listCredentialAccountsUseCase = listCredentialAccountsUseCase
        self.loadCredentialStatusUseCase = loadCredentialStatusUseCase
        self.removeCredentialsUseCase = removeCredentialsUseCase
        self.saveCredentialsUseCase = saveCredentialsUseCase
        self.credentialAccounts = Self.loadCredentialAccounts(
            listUseCase: listCredentialAccountsUseCase,
            statusUseCase: loadCredentialStatusUseCase
        )
    }

    convenience init() {
        let service = CredentialSettingsService()
        self.init(
            listCredentialAccountsUseCase: ListCredentialAccountsUseCase(settingsService: service),
            loadCredentialStatusUseCase: LoadCredentialStatusUseCase(settingsService: service),
            removeCredentialsUseCase: RemoveCredentialsUseCase(settingsService: service),
            saveCredentialsUseCase: SaveCredentialsUseCase(settingsService: service)
        )
    }

    func saveCredentials(account: String, gitHubAuth: GitHubAuth?, anthropicKey: String?) throws {
        credentialAccounts = try saveCredentialsUseCase.execute(
            account: account, gitHubAuth: gitHubAuth, anthropicKey: anthropicKey
        )
    }

    func removeCredentials(account: String) throws {
        credentialAccounts = try removeCredentialsUseCase.execute(account: account)
    }

    func credentialStatus(for account: String) -> CredentialStatus {
        loadCredentialStatusUseCase.execute(account: account)
    }

    private static func loadCredentialAccounts(
        listUseCase: ListCredentialAccountsUseCase,
        statusUseCase: LoadCredentialStatusUseCase
    ) -> [CredentialStatus] {
        guard let accounts = try? listUseCase.execute() else { return [] }
        return accounts.map { statusUseCase.execute(account: $0) }
    }
}
