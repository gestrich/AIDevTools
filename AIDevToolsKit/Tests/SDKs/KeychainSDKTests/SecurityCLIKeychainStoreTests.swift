#if os(macOS)
import Testing
@testable import KeychainSDK

@Suite("SecurityCLIKeychainStore")
struct SecurityCLIKeychainStoreTests {

    @Test("parseAccountKeys extracts accounts for matching service")
    func parseAccountKeysMatchingService() {
        let store = SecurityCLIKeychainStore(identifier: "com.gestrich.AIDevTools")
        let dump = """
        keychain: "/Users/test/Library/Keychains/login.keychain-db"
        version: 512
        class: "genp"
            0x00000007 <blob>="com.gestrich.AIDevTools"
            "svce"<blob>="com.gestrich.AIDevTools"
            "acct"<blob>="work/github-token"
        class: "genp"
            0x00000007 <blob>="com.gestrich.AIDevTools"
            "svce"<blob>="com.gestrich.AIDevTools"
            "acct"<blob>="work/anthropic-api-key"
        class: "genp"
            0x00000007 <blob>="com.other.app"
            "svce"<blob>="com.other.app"
            "acct"<blob>="other-key"
        """
        let keys = store.parseAccountKeys(from: dump, service: "com.gestrich.AIDevTools")
        #expect(keys == ["work/github-token", "work/anthropic-api-key"])
    }

    @Test("parseAccountKeys returns empty set for no matches")
    func parseAccountKeysNoMatches() {
        let store = SecurityCLIKeychainStore(identifier: "com.gestrich.AIDevTools")
        let dump = """
        class: "genp"
            "svce"<blob>="com.other.app"
            "acct"<blob>="some-key"
        """
        let keys = store.parseAccountKeys(from: dump, service: "com.gestrich.AIDevTools")
        #expect(keys.isEmpty)
    }

    @Test("parseAccountKeys handles empty dump")
    func parseAccountKeysEmptyDump() {
        let store = SecurityCLIKeychainStore(identifier: "com.gestrich.AIDevTools")
        let keys = store.parseAccountKeys(from: "", service: "com.gestrich.AIDevTools")
        #expect(keys.isEmpty)
    }

    @Test("parseAccountKeys skips entries with empty account")
    func parseAccountKeysSkipsEmptyAccount() {
        let store = SecurityCLIKeychainStore(identifier: "com.gestrich.AIDevTools")
        let dump = """
        class: "genp"
            "svce"<blob>="com.gestrich.AIDevTools"
            "acct"<blob>=""
        """
        let keys = store.parseAccountKeys(from: dump, service: "com.gestrich.AIDevTools")
        #expect(keys.isEmpty)
    }
}
#endif
