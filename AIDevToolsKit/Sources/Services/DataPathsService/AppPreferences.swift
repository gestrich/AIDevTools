import Foundation

public struct AppPreferences: Sendable {
    private static let suiteName = "org.gestrich.AIDevTools.shared"
    private static let aiDevToolsRepoPathKey = "AIDevTools.aiDevToolsRepoPath"
    private static let anthropicAPIEnabledKey = "experimental.anthropicAPIEnabled"
    private static let codexEnabledKey = "experimental.codexEnabled"
    private static let dataPathKey = "AIDevTools.dataPath"
    public static let defaultDataPath = URL.homeDirectory.appending(path: "Desktop/ai-dev-tools")

    public init() {}

    public func isAnthropicAPIEnabled() -> Bool {
        UserDefaults(suiteName: Self.suiteName)?.bool(forKey: Self.anthropicAPIEnabledKey) ?? false
    }

    public func setAnthropicAPIEnabled(_ enabled: Bool) {
        UserDefaults(suiteName: Self.suiteName)?.set(enabled, forKey: Self.anthropicAPIEnabledKey)
    }

    public func isCodexEnabled() -> Bool {
        UserDefaults(suiteName: Self.suiteName)?.bool(forKey: Self.codexEnabledKey) ?? false
    }

    public func setCodexEnabled(_ enabled: Bool) {
        UserDefaults(suiteName: Self.suiteName)?.set(enabled, forKey: Self.codexEnabledKey)
    }

    public func aiDevToolsRepoPath() -> URL? {
        guard let stored = UserDefaults(suiteName: Self.suiteName)?.string(forKey: Self.aiDevToolsRepoPathKey) else {
            return nil
        }
        return URL(filePath: stored)
    }

    public func setAIDevToolsRepoPath(_ path: URL?) {
        UserDefaults(suiteName: Self.suiteName)?.set(path?.path(), forKey: Self.aiDevToolsRepoPathKey)
    }

    public func dataPath() -> URL? {
        guard let stored = UserDefaults(suiteName: Self.suiteName)?.string(forKey: Self.dataPathKey) else {
            return nil
        }
        return URL(filePath: stored)
    }

    public func setDataPath(_ path: URL) {
        UserDefaults(suiteName: Self.suiteName)?.set(path.path(), forKey: Self.dataPathKey)
    }
}
