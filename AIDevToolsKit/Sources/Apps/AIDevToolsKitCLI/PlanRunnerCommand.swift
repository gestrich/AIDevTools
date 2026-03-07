import ArgumentParser

struct PlanRunnerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan-runner",
        abstract: "Voice-driven plan generation and phased execution",
        subcommands: [PlanRunnerDeleteCommand.self, PlanRunnerExecuteCommand.self, PlanRunnerPlanCommand.self]
    )
}
