import Foundation

public struct RepositoryStoreConfiguration: Sendable {
    public let dataPath: URL

    public init(dataPath: URL) {
        self.dataPath = dataPath
    }
}
