import AIOutputSDK
import Foundation

public struct ListSessionsUseCase: Sendable {

    public struct Options: Sendable {
        public let workingDirectory: String

        public init(workingDirectory: String) {
            self.workingDirectory = workingDirectory
        }
    }

    private let client: any AIClient

    public init(client: any AIClient) {
        self.client = client
    }

    public func run(_ options: Options) async -> [ChatSession] {
        await client.listSessions(workingDirectory: options.workingDirectory)
    }
}
