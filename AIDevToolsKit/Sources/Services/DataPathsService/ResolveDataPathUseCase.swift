import Foundation

public struct ResolveDataPathUseCase: Sendable {

    public enum Source: Sendable {
        case explicit
        case userDefaults
        case defaultPath
    }

    public struct Result: Sendable {
        public let path: URL
        public let source: Source
    }

    public static let suiteName = "org.gestrich.AIDevTools.shared"
    public static let dataPathKey = "AIDevTools.dataPath"
    public static let defaultRootPath = URL.homeDirectory.appending(path: "Desktop/ai-dev-tools")

    public init() {}

    public func resolve(explicit: String? = nil) -> Result {
        if let explicit {
            return Result(path: URL(filePath: explicit), source: .explicit)
        }
        if let stored = UserDefaults(suiteName: Self.suiteName)?.string(forKey: Self.dataPathKey) {
            return Result(path: URL(filePath: stored), source: .userDefaults)
        }
        return Result(path: Self.defaultRootPath, source: .defaultPath)
    }

    public func save(_ path: URL) {
        UserDefaults(suiteName: Self.suiteName)?.set(path.path(), forKey: Self.dataPathKey)
    }
}
