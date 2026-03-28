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

        let useCase = SendChatMessageUseCase(client: client)
        let dir = workingDir ?? FileManager.default.currentDirectoryPath

        if let message {
            try await sendMessage(message, workingDirectory: dir, useCase: useCase, client: client)
        } else {
            try await runInteractive(workingDirectory: dir, useCase: useCase, client: client)
        }
    }

    private func sendMessage(
        _ text: String,
        workingDirectory: String,
        useCase: SendChatMessageUseCase,
        client: any AIClient
    ) async throws {
        var sessionId: String?
        if resume, let listable = client as? SessionListable {
            let sessions = await listable.listSessions(workingDirectory: workingDirectory)
            sessionId = sessions.first?.id
        }

        let options = SendChatMessageUseCase.Options(
            message: text,
            workingDirectory: workingDirectory,
            sessionId: sessionId,
            systemPrompt: systemPrompt
        )

        let result = try await useCase.run(options) { progress in
            switch progress {
            case .streamEvent(let event):
                if case .textDelta(let text) = event {
                    print(text, terminator: "")
                    fflush(stdout)
                }
            case .completed:
                print()
            }
        }

        if result.exitCode != 0 {
            throw ExitCode(result.exitCode)
        }
    }

    private func runInteractive(
        workingDirectory: String,
        useCase: SendChatMessageUseCase,
        client: any AIClient
    ) async throws {
        print("\(client.displayName) Chat (type 'exit' or Ctrl-D to quit)")
        print("\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}")

        var sessionId: String?

        if resume, let listable = client as? SessionListable {
            let sessions = await listable.listSessions(workingDirectory: workingDirectory)
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

            let options = SendChatMessageUseCase.Options(
                message: input,
                workingDirectory: workingDirectory,
                sessionId: sessionId,
                systemPrompt: systemPrompt
            )

            print("\n\(client.displayName): ", terminator: "")
            fflush(stdout)

            do {
                let result = try await useCase.run(options) { progress in
                    switch progress {
                    case .streamEvent(let event):
                        if case .textDelta(let text) = event {
                            print(text, terminator: "")
                            fflush(stdout)
                        }
                    case .completed:
                        print()
                    }
                }
                sessionId = result.sessionId ?? sessionId
            } catch {
                print("\nError: \(error.localizedDescription)")
            }
        }
    }
}
