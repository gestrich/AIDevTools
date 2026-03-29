import Testing
@testable import KeychainSDK

@Suite("EnvironmentKeychainStore")
struct EnvironmentKeychainStoreTests {

    @Test("resolves github-token from GITHUB_TOKEN env var")
    func resolvesGitHubToken() throws {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_TOKEN": "ghp_abc123"])
        let value = try store.string(forKey: "myaccount/github-token")
        #expect(value == "ghp_abc123")
    }

    @Test("resolves anthropic-api-key from ANTHROPIC_API_KEY env var")
    func resolvesAnthropicKey() throws {
        let store = EnvironmentKeychainStore(environment: ["ANTHROPIC_API_KEY": "sk-ant-test"])
        let value = try store.string(forKey: "work/anthropic-api-key")
        #expect(value == "sk-ant-test")
    }

    @Test("resolves github-app-id from GITHUB_APP_ID env var")
    func resolvesGitHubAppId() throws {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_APP_ID": "12345"])
        let value = try store.string(forKey: "myaccount/github-app-id")
        #expect(value == "12345")
    }

    @Test("resolves github-app-installation-id from GITHUB_APP_INSTALLATION_ID env var")
    func resolvesGitHubAppInstallationId() throws {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_APP_INSTALLATION_ID": "67890"])
        let value = try store.string(forKey: "myaccount/github-app-installation-id")
        #expect(value == "67890")
    }

    @Test("resolves github-app-private-key from GITHUB_APP_PRIVATE_KEY env var")
    func resolvesGitHubAppPrivateKey() throws {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_APP_PRIVATE_KEY": "-----BEGIN RSA"])
        let value = try store.string(forKey: "myaccount/github-app-private-key")
        #expect(value == "-----BEGIN RSA")
    }

    @Test("throws itemNotFound for missing env var")
    func throwsForMissingEnvVar() {
        let store = EnvironmentKeychainStore(environment: [:])
        #expect(throws: KeychainStoreError.self) {
            try store.string(forKey: "myaccount/github-token")
        }
    }

    @Test("throws itemNotFound for empty env var")
    func throwsForEmptyEnvVar() {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_TOKEN": ""])
        #expect(throws: KeychainStoreError.self) {
            try store.string(forKey: "myaccount/github-token")
        }
    }

    @Test("throws itemNotFound for unknown key type")
    func throwsForUnknownKeyType() {
        let store = EnvironmentKeychainStore(environment: ["SOME_VAR": "value"])
        #expect(throws: KeychainStoreError.self) {
            try store.string(forKey: "myaccount/unknown-type")
        }
    }

    @Test("throws itemNotFound for key without slash")
    func throwsForKeyWithoutSlash() {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_TOKEN": "ghp_abc"])
        #expect(throws: KeychainStoreError.self) {
            try store.string(forKey: "github-token")
        }
    }

    @Test("setString throws readOnly")
    func setStringThrowsReadOnly() {
        let store = EnvironmentKeychainStore(environment: [:])
        #expect(throws: KeychainStoreError.self) {
            try store.setString("value", forKey: "account/github-token")
        }
    }

    @Test("removeObject throws readOnly")
    func removeObjectThrowsReadOnly() {
        let store = EnvironmentKeychainStore(environment: [:])
        #expect(throws: KeychainStoreError.self) {
            try store.removeObject(forKey: "account/github-token")
        }
    }

    @Test("allKeys returns keys for set env vars")
    func allKeysReturnsSetEnvVars() throws {
        let store = EnvironmentKeychainStore(environment: [
            "GITHUB_TOKEN": "ghp_abc",
            "ANTHROPIC_API_KEY": "sk-ant-test",
        ])
        let keys = try store.allKeys()
        #expect(keys.contains("env/github-token"))
        #expect(keys.contains("env/anthropic-api-key"))
        #expect(!keys.contains("env/github-app-id"))
    }

    @Test("allKeys returns empty set when no env vars set")
    func allKeysReturnsEmptySetWhenNoEnvVars() throws {
        let store = EnvironmentKeychainStore(environment: [:])
        let keys = try store.allKeys()
        #expect(keys.isEmpty)
    }

    @Test("account portion of key is ignored for resolution")
    func accountPortionIgnored() throws {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_TOKEN": "ghp_abc"])
        let value1 = try store.string(forKey: "account1/github-token")
        let value2 = try store.string(forKey: "account2/github-token")
        #expect(value1 == value2)
    }
}
