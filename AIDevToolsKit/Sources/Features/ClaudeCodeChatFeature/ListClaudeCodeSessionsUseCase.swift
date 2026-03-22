import ClaudeCodeChatService
import Foundation

public struct ListClaudeCodeSessionsUseCase: Sendable {

    public struct Options: Sendable {
        public let workingDirectory: String

        public init(workingDirectory: String) {
            self.workingDirectory = workingDirectory
        }
    }

    public init() {}

    @MainActor
    public func run(_ options: Options) async -> [ClaudeSession] {
        let manager = ClaudeCodeChatManager(workingDirectory: options.workingDirectory)
        return await manager.listSessions()
    }
}
