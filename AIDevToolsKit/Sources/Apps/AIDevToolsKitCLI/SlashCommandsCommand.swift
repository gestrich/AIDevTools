import ArgumentParser
import ClaudeCodeChatFeature
import Foundation

struct SlashCommandsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "slash-commands",
        abstract: "List available skills (formerly slash commands)"
    )

    @Option(name: .long, help: "Working directory to scan (defaults to current directory)")
    var workingDir: String?

    func run() throws {
        let dir = workingDir ?? FileManager.default.currentDirectoryPath
        let useCase = ScanSkillsUseCase()
        let skills = try useCase.run(.init(workingDirectory: dir))

        if skills.isEmpty {
            print("No skills found.")
            return
        }

        print("Found \(skills.count) skill(s):\n")
        for skill in skills {
            print("  /\(skill.name)")
            print("    \(skill.path.path())")
        }
    }
}
