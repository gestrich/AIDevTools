import ArgumentParser
import ClaudeChainCLI
import Foundation
import Logging

@main
struct AIDevToolsKit: AsyncParsableCommand {
    nonisolated(unsafe) static var bootstrapped = false

    static let configuration = CommandConfiguration(
        commandName: "ai-dev-tools-kit",
        abstract: "Developer tools for AI-assisted workflows",
        subcommands: subcommandTypes
    )

    static func main() async {
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? any AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            exit(withError: error)
        }
    }

    private static var subcommandTypes: [any ParsableCommand.Type] {
        var commands: [any ParsableCommand.Type] = [
            ChatCommand.self, ClaudeChainCLI.self, ClearArtifactsCommand.self, ConfigCommand.self, CredentialsCommand.self, ListCasesCommand.self, LogsCommand.self, MCPCommand.self, PlanCommand.self, PRRadarCommand.self, ReposCommand.self, RunEvalsCommand.self, ShowEvalOutputCommand.self, SkillsCommand.self, SweepCommand.self, WorktreeCommand.self,
        ]
        #if canImport(SwiftData)
        commands.insert(ArchPlannerCommand.self, at: 0)
        #endif
        return commands
    }

    @Option(name: .long, help: "Log level: trace, debug, info, notice, warning, error, critical")
    var logLevel: Logger.Level = .info

    mutating func validate() throws {
        guard !Self.bootstrapped else { return }
        CLICompositionRoot.preServiceSetup(logLevel: logLevel)
        Self.bootstrapped = true
    }

}

extension Logger.Level: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}
