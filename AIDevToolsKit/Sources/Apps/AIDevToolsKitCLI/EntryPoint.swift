import ArgumentParser

@main
struct AIDevToolsKit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ai-dev-tools-kit",
        abstract: "Developer tools for AI-assisted workflows",
        subcommands: [ChatCommand.self, ClaudeChatCommand.self, ClearArtifactsCommand.self, ListCasesCommand.self, PlanRunnerCommand.self, ReposCommand.self, RunEvalsCommand.self, ShowOutputCommand.self, SkillsCommand.self, SlashCommandsCommand.self]
    )
}
