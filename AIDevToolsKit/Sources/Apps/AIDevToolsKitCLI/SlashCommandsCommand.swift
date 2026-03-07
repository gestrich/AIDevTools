import ArgumentParser
import ClaudeCodeChatFeature
import Foundation

struct SlashCommandsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "slash-commands",
        abstract: "List available Claude slash commands"
    )

    @Option(name: .long, help: "Working directory to scan (defaults to current directory)")
    var workingDir: String?

    func run() throws {
        let dir = workingDir ?? FileManager.default.currentDirectoryPath
        let useCase = ScanSlashCommandsUseCase()
        let commands = useCase.run(.init(workingDirectory: dir))

        if commands.isEmpty {
            print("No slash commands found.")
            return
        }

        print("Found \(commands.count) slash command(s):\n")
        for command in commands {
            print("  \(command.name)")
            print("    \(command.path)")
        }
    }
}
