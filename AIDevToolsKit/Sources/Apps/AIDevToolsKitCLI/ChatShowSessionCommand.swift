import AIOutputSDK
import ArgumentParser
import ChatFeature
import Foundation
import ProviderRegistryService

struct ChatShowSessionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show-session",
        abstract: "Show the message transcript for a specific chat session"
    )

    @Argument(help: "Session ID to display")
    var sessionId: String

    @Option(name: .long, help: "Provider to use (default: first registered)")
    var provider: String?

    @Option(name: .long, help: "Working directory (defaults to current directory)")
    var workingDir: String?

    func run() async throws {
        let registry = makeProviderRegistry()
        let client = try resolveClient(named: provider, from: registry)
        let dir = workingDir ?? FileManager.default.currentDirectoryPath
        let useCase = LoadSessionMessagesUseCase(client: client)
        let messages = await useCase.run(.init(sessionId: sessionId, workingDirectory: dir))

        if messages.isEmpty {
            print("No messages found for session \(sessionId).")
            return
        }

        print("Session: \(sessionId)")
        print(String(repeating: "─", count: 49))

        for message in messages {
            let roleLabel = message.role == .user ? "You" : client.displayName
            print("\n\(roleLabel):")
            for block in message.contentBlocks {
                if case .text(let text) = block {
                    print(text)
                }
            }
        }
    }
}
