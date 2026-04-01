import Foundation

public struct AppPreferences: Sendable {
    private static let suiteName = "org.gestrich.AIDevTools.shared"
    private static let dataPathKey = "AIDevTools.dataPath"
    public static let defaultDataPath = URL.homeDirectory.appending(path: "Desktop/ai-dev-tools")

    public init() {}

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
