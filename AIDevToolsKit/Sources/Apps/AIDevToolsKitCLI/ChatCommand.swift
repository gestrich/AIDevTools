import AnthropicChatFeature
import AnthropicSDK
import ArgumentParser
import Foundation

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
        let client = AnthropicAIClient(apiClient: AnthropicAPIClient(apiKey: key))

        if let message {
            try await sendSingleMessage(message, client: client)
        } else {
            try await runInteractive(client: client)
        }
    }

    // MARK: - Private

    private var resolvedAPIKey: String? {
        apiKey ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
    }

    private func sendSingleMessage(_ text: String, client: AnthropicAIClient) async throws {
        let useCase = SendChatMessageUseCase(client: client)
        let options = SendChatMessageUseCase.Options(
            message: text,
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

    private func runInteractive(client: AnthropicAIClient) async throws {
        print("Chat with Claude (type 'exit' or Ctrl-D to quit)")
        print("─────────────────────────────────────────────────")

        let useCase = SendChatMessageUseCase(client: client)
        var sessionId: String?

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
}
