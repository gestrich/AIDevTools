import AIOutputSDK
import AnthropicChatFeature
import AnthropicSDK
import ArgumentParser
import ClaudeCodeChatFeature
import ClaudeCLISDK
import Foundation
import ProviderRegistryService

struct ChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Chat with an AI provider"
    )

    @Option(name: .long, help: "Provider to use for chat (default: claude)")
    var provider: String = "claude"

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

        guard let client = registry.client(named: provider) else {
            print("Unknown provider '\(provider)'. Available: \(registry.providerNames.joined(separator: ", "))")
            throw ExitCode.failure
        }

        if client is AnthropicAIClient {
            try await runAnthropicChat(client: client)
        } else {
            try await runCLIChat(client: client)
        }
    }

    // MARK: - Anthropic API Chat

    private func runAnthropicChat(client: any AIClient) async throws {
        if let message {
            try await sendAnthropicMessage(message, client: client)
        } else {
            try await runAnthropicInteractive(client: client)
        }
    }

    private func sendAnthropicMessage(_ text: String, client: any AIClient) async throws {
        let useCase = SendChatMessageUseCase(client: client)
        var sessionId: String?
        if resume, let listable = client as? SessionListable {
            let dir = workingDir ?? FileManager.default.currentDirectoryPath
            let sessions = await listable.listSessions(workingDirectory: dir)
            sessionId = sessions.first?.id
        }

        let options = SendChatMessageUseCase.Options(
            message: text,
            sessionId: sessionId,
            systemPrompt: systemPrompt
        )

        _ = try await useCase.run(options) { progress in
            switch progress {
            case .textDelta(let text):
                print(text, terminator: "")
                fflush(stdout)
            case .completed:
                print()
            }
        }
    }

    private func runAnthropicInteractive(client: any AIClient) async throws {
        print("Anthropic API Chat (type 'exit' or Ctrl-D to quit)")
        print("\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}")

        let useCase = SendChatMessageUseCase(client: client)
        var sessionId: String?

        if resume, let listable = client as? SessionListable {
            let dir = workingDir ?? FileManager.default.currentDirectoryPath
            let sessions = await listable.listSessions(workingDirectory: dir)
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
                sessionId: sessionId,
                systemPrompt: systemPrompt
            )

            print("\nClaude: ", terminator: "")
            fflush(stdout)

            do {
                let result = try await useCase.run(options) { progress in
                    switch progress {
                    case .textDelta(let text):
                        print(text, terminator: "")
                        fflush(stdout)
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

    // MARK: - CLI Chat (Claude, Codex, etc.)

    private func runCLIChat(client: any AIClient) async throws {
        let dir = workingDir ?? FileManager.default.currentDirectoryPath

        if let message {
            try await sendCLIMessage(message, workingDirectory: dir, client: client)
        } else {
            try await runCLIInteractive(workingDirectory: dir, client: client)
        }
    }

    private func sendCLIMessage(_ text: String, workingDirectory: String, client: any AIClient) async throws {
        let useCase = SendClaudeCodeMessageUseCase(client: client)
        var sessionId: String?
        if resume, let listable = client as? SessionListable {
            let sessions = await listable.listSessions(workingDirectory: workingDirectory)
            sessionId = sessions.first?.id
        }

        let options = SendClaudeCodeMessageUseCase.Options(
            message: text,
            workingDirectory: workingDirectory,
            sessionId: sessionId
        )

        _ = try await useCase.run(options) { progress in
            switch progress {
            case .textDelta(let text):
                print(text, terminator: "")
                fflush(stdout)
            case .completed:
                print()
            }
        }
    }

    private func runCLIInteractive(workingDirectory: String, client: any AIClient) async throws {
        print("\(client.displayName) Chat (type 'exit' or Ctrl-D to quit)")
        print("\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}")

        let useCase = SendClaudeCodeMessageUseCase(client: client)
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

            let options = SendClaudeCodeMessageUseCase.Options(
                message: input,
                workingDirectory: workingDirectory,
                sessionId: sessionId
            )

            print("\n\(client.displayName): ", terminator: "")
            fflush(stdout)

            do {
                let result = try await useCase.run(options) { progress in
                    switch progress {
                    case .textDelta(let text):
                        print(text, terminator: "")
                        fflush(stdout)
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
