import AIOutputSDK
import ArgumentParser
import ChatFeature
import Foundation
import ProviderRegistryService

struct ChatListSessionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-sessions",
        abstract: "List available chat sessions"
    )

    @Option(name: .long, help: "Provider to use (default: first registered)")
    var provider: String?

    @Option(name: .long, help: "Working directory (defaults to current directory)")
    var workingDir: String?

    func run() async throws {
        let registry = makeProviderRegistry()
        let client = try resolveClient(named: provider, from: registry)
        let dir = workingDir ?? FileManager.default.currentDirectoryPath
        let useCase = ListSessionsUseCase(client: client)
        let sessions = await useCase.run(.init(workingDirectory: dir))

        if sessions.isEmpty {
            print("No sessions found.")
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        for session in sessions {
            print("\(session.id)  \(dateFormatter.string(from: session.lastModified))  \(session.summary)")
        }
    }
}
