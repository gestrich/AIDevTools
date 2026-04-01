import CredentialService
import Foundation

@MainActor @Observable
final class AppModel {
    let providerModel: ProviderModel

    init(providerModel: ProviderModel) {
        self.providerModel = providerModel
    }

    func applyCredentialChange(_ type: CredentialType) {
        switch type {
        case .anthropicAPIKey:
            providerModel.refreshProviders()
        case .githubToken:
            break
        }
    }
}
