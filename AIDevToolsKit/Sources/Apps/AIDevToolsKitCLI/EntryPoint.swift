import ArgumentParser
import LoggingSDK

@main
struct AIDevToolsKit: AsyncParsableCommand {
    nonisolated(unsafe) static var loggingBootstrapped = false

    static let configuration = CommandConfiguration(
        commandName: "ai-dev-tools-kit",
        abstract: "Developer tools for AI-assisted workflows",
        subcommands: [ArchPlannerCommand.self, ChatCommand.self, ClaudeChatCommand.self, ClearArtifactsCommand.self, ConfigCommand.self, ListCasesCommand.self, PlanRunnerCommand.self, ReposCommand.self, RunEvalsCommand.self, ShowOutputCommand.self, SkillsCommand.self]
    )

    mutating func validate() throws {
        guard !Self.loggingBootstrapped else { return }
        AIDevToolsLogging.bootstrap()
        Self.loggingBootstrapped = true
    }
}
