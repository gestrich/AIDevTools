import Foundation
import UseCaseSDK

public struct ResolveDataPathUseCase: UseCase {

    public enum Source: Sendable {
        case explicit
        case userDefaults
        case defaultPath
    }

    public struct Result: Sendable {
        public let path: URL
        public let source: Source
    }

    public init() {}

    public func resolve(explicit: String? = nil) -> Result {
        if let explicit {
            return Result(path: URL(filePath: explicit), source: .explicit)
        }
        if let stored = AppPreferences().dataPath() {
            return Result(path: stored, source: .userDefaults)
        }
        return Result(path: AppPreferences.defaultDataPath, source: .defaultPath)
    }

    public func save(_ path: URL) {
        AppPreferences().setDataPath(path)
    }
}
