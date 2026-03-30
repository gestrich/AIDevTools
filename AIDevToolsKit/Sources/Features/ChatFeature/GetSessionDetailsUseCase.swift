import AIOutputSDK
import Foundation
import UseCaseSDK

public struct GetSessionDetailsUseCase: UseCase {

    public struct Options: Sendable {
        public let lastModified: Date
        public let sessionId: String
        public let summary: String
        public let workingDirectory: String

        public init(sessionId: String, summary: String, lastModified: Date, workingDirectory: String) {
            self.lastModified = lastModified
            self.sessionId = sessionId
            self.summary = summary
            self.workingDirectory = workingDirectory
        }
    }

    private let client: any AIClient

    public init(client: any AIClient) {
        self.client = client
    }

    public func run(_ options: Options) -> SessionDetails? {
        client.getSessionDetails(sessionId: options.sessionId, summary: options.summary, lastModified: options.lastModified, workingDirectory: options.workingDirectory)
    }
}
