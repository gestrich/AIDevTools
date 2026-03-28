import AIOutputSDK
import ArgumentParser
import ChatFeature
import Foundation
import ProviderRegistryService

struct ChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Chat with an AI provider"
    )

    @Option(name: .long, help: "Provider to use for chat (default: first registered)")
    var provider: String?

    @Option(name: .long, help: "System prompt to configure the AI's behavior")
    var systemPrompt: String?

    @Option(name: .long, help: "Working directory (defaults to current directory)")
    var workingDir: String?

    @Flag(name: .long, help: "Resume the last session")
    var resume: Bool = false

    @Argument(help: "Single message to send (omit for interactive mode)")
    var message: String?

    func run() async throws {
        let registry = makeProviderRegistry()

        let client: any AIClient
        if let provider {
            guard let named = registry.client(named: provider) else {
                print("Unknown provider '\(provider)'. Available: \(registry.providerNames.joined(separator: ", "))")
                throw ExitCode.failure
            }
            client = named
        } else {
            guard let defaultClient = registry.defaultClient else {
                print("No providers registered.")
                throw ExitCode.failure
            }
            client = defaultClient
        }

        let chatProvider = AIClientChatAdapter.make(from: client)
        let dir = workingDir ?? FileManager.default.currentDirectoryPath

        if let message {
            try await sendMessage(message, workingDirectory: dir, chatProvider: chatProvider)
        } else {
            try await runInteractive(workingDirectory: dir, chatProvider: chatProvider)
        }
    }

    private func sendMessage(
        _ text: String,
        workingDirectory: String,
        chatProvider: any ChatProvider
    ) async throws {
        var sessionId: String?
        if resume, chatProvider.supportsSessionHistory {
            let sessions = await chatProvider.listSessions(workingDirectory: workingDirectory)
            sessionId = sessions.first?.id
        }

        let options = ChatProviderOptions(
            sessionId: sessionId,
            systemPrompt: systemPrompt,
            workingDirectory: workingDirectory
        )

        let result = try await chatProvider.sendMessage(
            text,
            images: [],
            options: options
        ) { event in
            if case .textDelta(let text) = event {
                print(text, terminator: "")
                fflush(stdout)
            }
        }
        print()

        if result.content.isEmpty && result.sessionId == nil {
            throw ExitCode.failure
        }
    }

    private func runInteractive(
        workingDirectory: String,
        chatProvider: any ChatProvider
    ) async throws {
        print("\(chatProvider.displayName) Chat (type 'exit' or Ctrl-D to quit)")
        print("\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}")

        var sessionId: String?

        if resume, chatProvider.supportsSessionHistory {
            let sessions = await chatProvider.listSessions(workingDirectory: workingDirectory)
            sessionId = sessions.first?.id
            if let sessionId {
                print("Resuming session: \(sessionId)")
            }
        }

        while true {
            print("\nYou: ", terminator: "")
            fflush(stdout)

            guard let line = readLine(strippingNewline: true) else {
                print()
                break
            }

            let input = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if input.isEmpty { continue }
            if input.lowercased() == "exit" { break }

            let options = ChatProviderOptions(
                sessionId: sessionId,
                systemPrompt: systemPrompt,
                workingDirectory: workingDirectory
            )

            print("\n\(chatProvider.displayName): ", terminator: "")
            fflush(stdout)

            do {
                let result = try await chatProvider.sendMessage(
                    input,
                    images: [],
                    options: options
                ) { event in
                    if case .textDelta(let text) = event {
                        print(text, terminator: "")
                        fflush(stdout)
                    }
                }
                print()
                sessionId = result.sessionId ?? sessionId
            } catch {
                print("\nError: \(error.localizedDescription)")
            }
        }
    }
}
