import AIOutputSDK
import ArgumentParser
import ChatFeature
import Foundation
import ProviderRegistryService

struct ChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Chat with an AI provider",
        subcommands: [ChatListSessionsCommand.self]
    )

    @Option(name: .long, help: "Provider to use for chat (default: first registered)")
    var provider: String?

    @Option(name: .long, help: "Session ID to resume")
    var sessionId: String?

    @Option(name: .long, help: "System prompt to configure the AI's behavior")
    var systemPrompt: String?

    @Option(name: .long, help: "Working directory (defaults to current directory)")
    var workingDir: String?

    @Option(name: .long, help: "Path to MCP config JSON (default: AIDevTools app config)")
    var mcpConfig: String?

    @Flag(name: .long, help: "Resume the last session")
    var resume: Bool = false

    @Argument(help: "Single message to send (omit for interactive mode)")
    var message: String?

    func run() async throws {
        let registry = makeProviderRegistry()
        let client = try resolveClient(named: provider, from: registry)
        let useCase = SendChatMessageUseCase(client: client)
        let dir = workingDir ?? FileManager.default.currentDirectoryPath

        if let message {
            try await sendMessage(message, workingDirectory: dir, useCase: useCase, client: client)
        } else {
            try await runInteractive(workingDirectory: dir, useCase: useCase, client: client)
        }
    }

    private func resolveInitialSessionId(client: any AIClient, workingDirectory: String, verbose: Bool) async -> String? {
        if let explicitSessionId = sessionId {
            if verbose { print("Resuming session: \(explicitSessionId)") }
            return explicitSessionId
        } else if resume {
            let sessions = await client.listSessions(workingDirectory: workingDirectory)
            if let id = sessions.first?.id {
                if verbose { print("Resuming session: \(id)") }
                return id
            }
        }
        return nil
    }

    private func sendMessage(
        _ text: String,
        workingDirectory: String,
        useCase: SendChatMessageUseCase,
        client: any AIClient
    ) async throws {
        let activeSessionId = await resolveInitialSessionId(client: client, workingDirectory: workingDirectory, verbose: false)

        let options = SendChatMessageUseCase.Options(
            message: text,
            workingDirectory: workingDirectory,
            sessionId: activeSessionId,
            mcpConfigPath: mcpConfig,
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

        var activeSessionId = await resolveInitialSessionId(client: client, workingDirectory: workingDirectory, verbose: true)

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
                sessionId: activeSessionId,
                mcpConfigPath: mcpConfig,
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
                activeSessionId = result.sessionId ?? activeSessionId
            } catch {
                print("\nError: \(error.localizedDescription)")
            }
        }
    }
}
