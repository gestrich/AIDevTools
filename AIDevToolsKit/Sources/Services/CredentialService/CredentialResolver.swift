import EnvironmentSDK
import Foundation

public struct CredentialResolver: Sendable {
    public static let anthropicAPIKeyKey = "ANTHROPIC_API_KEY"
    public static let gitHubAppIdKey = "GITHUB_APP_ID"
    public static let gitHubAppInstallationIdKey = "GITHUB_APP_INSTALLATION_ID"
    public static let gitHubAppPrivateKeyKey = "GITHUB_APP_PRIVATE_KEY"
    public static let githubTokenKey = "GITHUB_TOKEN"

    private let account: String
    private let dotEnv: [String: String]
    private let explicitToken: String?
    private let processEnvironment: [String: String]
    private let settingsService: SecureSettingsService?

    public init(
        settingsService: SecureSettingsService,
        githubAccount: String,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        dotEnv: [String: String]? = nil
    ) {
        self.account = githubAccount
        self.dotEnv = dotEnv ?? DotEnvironmentLoader.loadDotEnv()
        self.explicitToken = nil
        self.processEnvironment = processEnvironment
        self.settingsService = settingsService
    }

    private init(explicitToken: String) {
        self.account = ""
        self.dotEnv = [:]
        self.explicitToken = explicitToken
        self.processEnvironment = [:]
        self.settingsService = nil
    }

    public static func withExplicitToken(_ token: String) -> CredentialResolver {
        CredentialResolver(explicitToken: token)
    }

    public func getGitHubAuth() -> GitHubAuth? {
        if let token = explicitToken {
            return .token(token)
        }
        if let auth = resolveGitHubAppAuth() {
            return auth
        }
        // Named env key (process env first, then dotEnv)
        let namedTokenKey = "\(Self.githubTokenKey)_\(account)"
        if let token = processEnvironment[namedTokenKey] ?? dotEnv[namedTokenKey] {
            return .token(token)
        }
        // Keychain
        if let service = settingsService,
           let token = try? service.loadCredential(account: account, type: SecureSettingsService.gitHubTokenType) {
            return .token(token)
        }
        // Unnamed env keys
        if let token = processEnvironment[Self.githubTokenKey] ?? dotEnv[Self.githubTokenKey] {
            return .token(token)
        }
        if let token = processEnvironment["GH_TOKEN"] ?? dotEnv["GH_TOKEN"] {
            return .token(token)
        }
        return nil
    }

    public func requireGitHubAuth() throws -> GitHubAuth {
        guard let auth = getGitHubAuth() else {
            throw CredentialError.notConfigured(account: account)
        }
        return auth
    }

    /// Environment dict to pass to child processes (e.g. GitClient) so they inherit the GitHub token.
    public var gitEnvironment: [String: String]? {
        guard case .token(let token) = getGitHubAuth() else { return nil }
        return ["GH_TOKEN": token]
    }

    public func getAnthropicKey() -> String? {
        resolveValue(envKey: Self.anthropicAPIKeyKey, keychainType: SecureSettingsService.anthropicKeyType)
    }

    private func resolveGitHubAppAuth() -> GitHubAuth? {
        // Named env keys first
        let namedAppIdKey = "\(Self.gitHubAppIdKey)_\(account)"
        let namedInstallationIdKey = "\(Self.gitHubAppInstallationIdKey)_\(account)"
        let namedPrivateKeyKey = "\(Self.gitHubAppPrivateKeyKey)_\(account)"
        if let appId = processEnvironment[namedAppIdKey] ?? dotEnv[namedAppIdKey],
           let installationId = processEnvironment[namedInstallationIdKey] ?? dotEnv[namedInstallationIdKey],
           let privateKey = processEnvironment[namedPrivateKeyKey] ?? dotEnv[namedPrivateKeyKey] {
            return .app(appId: appId, installationId: installationId, privateKeyPEM: privateKey)
        }
        // Keychain
        if let service = settingsService,
           let appId = try? service.loadCredential(account: account, type: SecureSettingsService.gitHubAppIdType),
           let installationId = try? service.loadCredential(account: account, type: SecureSettingsService.gitHubAppInstallationIdType),
           let privateKey = try? service.loadCredential(account: account, type: SecureSettingsService.gitHubAppPrivateKeyType) {
            return .app(appId: appId, installationId: installationId, privateKeyPEM: privateKey)
        }
        // Unnamed env keys
        if let appId = processEnvironment[Self.gitHubAppIdKey] ?? dotEnv[Self.gitHubAppIdKey],
           let installationId = processEnvironment[Self.gitHubAppInstallationIdKey] ?? dotEnv[Self.gitHubAppInstallationIdKey],
           let privateKey = processEnvironment[Self.gitHubAppPrivateKeyKey] ?? dotEnv[Self.gitHubAppPrivateKeyKey] {
            return .app(appId: appId, installationId: installationId, privateKeyPEM: privateKey)
        }
        return nil
    }

    private func resolveValue(envKey: String, keychainType: String) -> String? {
        if let v = processEnvironment[envKey] { return v }
        if let v = dotEnv[envKey] { return v }
        if let service = settingsService {
            return try? service.loadCredential(account: account, type: keychainType)
        }
        return nil
    }
}
