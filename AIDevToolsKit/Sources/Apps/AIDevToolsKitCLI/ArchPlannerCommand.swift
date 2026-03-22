import ArgumentParser

struct ArchPlannerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "arch-planner",
        abstract: "Architecture-driven planning and implementation",
        subcommands: [
            ArchPlannerCreateCommand.self,
            ArchPlannerExecuteCommand.self,
            ArchPlannerGuidelinesCommand.self,
            ArchPlannerInspectCommand.self,
            ArchPlannerReportCommand.self,
            ArchPlannerScoreCommand.self,
            ArchPlannerUpdateCommand.self,
        ]
    )
}
