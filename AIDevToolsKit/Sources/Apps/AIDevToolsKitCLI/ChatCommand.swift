import AnthropicSDK
import ArgumentParser
import AnthropicChatFeature
import Foundation
@preconcurrency import SwiftAnthropic

struct ChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Chat with Claude via the Anthropic API"
    )

    @Option(name: .long, help: "Anthropic API key (or set ANTHROPIC_API_KEY env var)")
    var apiKey: String?

    @Option(name: .long, help: "System prompt to configure Claude's behavior")
    var systemPrompt: String?

    @Argument(help: "Single message to send (omit for interactive mode)")
    var message: String?

    func validate() throws {
        if resolvedAPIKey == nil {
            throw ValidationError("API key required. Use --api-key or set ANTHROPIC_API_KEY.")
        }
    }

    func run() async throws {
        let key = resolvedAPIKey!

        if let message {
            try await sendSingleMessage(message, apiKey: key)
        } else {
            try await runInteractive(apiKey: key)
        }
    }

    // MARK: - Private

    private var resolvedAPIKey: String? {
        apiKey ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
    }

    private func sendSingleMessage(_ text: String, apiKey: String) async throws {
        let useCase = SendChatMessageUseCase()
        let options = SendChatMessageUseCase.Options(
            message: text,
            apiKey: apiKey,
            systemPrompt: systemPrompt
        )

        _ = try await useCase.run(options) { progress in
            switch progress {
            case .textDelta(let text):
                print(text, terminator: "")
                fflush(stdout)
            case .toolUse(let name):
                print("\n[Using tool: \(name)]", terminator: "")
            case .completed:
                print()
            }
        }
    }

    private func runInteractive(apiKey: String) async throws {
        print("Chat with Claude (type 'exit' or Ctrl-D to quit)")
        print("─────────────────────────────────────────────────")

        let useCase = SendChatMessageUseCase()
        var history: [MessageParameter.Message] = []

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
                apiKey: apiKey,
                systemPrompt: systemPrompt
            )

            print("\nClaude: ", terminator: "")
            fflush(stdout)

            do {
                let response = try await useCase.run(options, history: history) { progress in
                    switch progress {
                    case .textDelta(let text):
                        print(text, terminator: "")
                        fflush(stdout)
                    case .toolUse(let name):
                        print("\n[Using tool: \(name)]", terminator: "")
                    case .completed:
                        print()
                    }
                }

                history.append(MessageParameter.Message(role: .user, content: .text(input)))
                history.append(MessageParameter.Message(role: .assistant, content: .text(response)))
            } catch {
                print("\nError: \(error.localizedDescription)")
            }
        }
    }
}
