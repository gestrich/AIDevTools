import ArgumentParser
import ClaudeCodeChatFeature
import ClaudeCodeChatService
import ClaudeCLISDK
import Foundation

struct ClaudeChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "claude-chat",
        abstract: "Chat with Claude via the Claude Code CLI"
    )

    @Option(name: .long, help: "Working directory (defaults to current directory)")
    var workingDir: String?

    @Flag(name: .long, help: "Resume the last session")
    var resume: Bool = false

    @Argument(help: "Single message to send (omit for interactive mode)")
    var message: String?

    func run() async throws {
        let dir = workingDir ?? FileManager.default.currentDirectoryPath

        if let message {
            try await sendSingleMessage(message, workingDirectory: dir)
        } else {
            try await runInteractive(workingDirectory: dir)
        }
    }

    // MARK: - Private

    private func sendSingleMessage(_ text: String, workingDirectory: String) async throws {
        let useCase = SendClaudeCodeMessageUseCase()
        var sessionId: String?
        if resume {
            let sessions = await ListClaudeCodeSessionsUseCase().run(
                .init(workingDirectory: workingDirectory)
            )
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

    private func runInteractive(workingDirectory: String) async throws {
        print("Claude Code Chat (type 'exit' or Ctrl-D to quit)")
        print("─────────────────────────────────────────────────")

        let useCase = SendClaudeCodeMessageUseCase()
        var sessionId: String?

        if resume {
            let sessions = await ListClaudeCodeSessionsUseCase().run(
                .init(workingDirectory: workingDirectory)
            )
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

            print("\nClaude: ", terminator: "")
            fflush(stdout)

            do {
                _ = try await useCase.run(options) { progress in
                    switch progress {
                    case .textDelta(let text):
                        print(text, terminator: "")
                        fflush(stdout)
                    case .completed:
                        print()
                    }
                }
            } catch {
                print("\nError: \(error.localizedDescription)")
            }
        }
    }
}
