import Foundation

public struct RepositoryStoreConfiguration: Sendable {
    public let dataPath: URL

    public init(dataPath: URL = URL.homeDirectory.appending(path: "Desktop/ai-dev-tools")) {
        self.dataPath = dataPath
    }
}
