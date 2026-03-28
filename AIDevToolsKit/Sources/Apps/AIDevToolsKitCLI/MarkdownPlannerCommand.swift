import ArgumentParser

struct MarkdownPlannerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "markdown-planner",
        abstract: "Voice-driven plan generation and phased execution",
        subcommands: [MarkdownPlannerDeleteCommand.self, MarkdownPlannerExecuteCommand.self, MarkdownPlannerPlanCommand.self]
    )
}
