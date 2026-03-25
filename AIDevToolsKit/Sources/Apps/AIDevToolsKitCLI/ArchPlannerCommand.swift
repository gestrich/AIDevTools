import ArgumentParser
import Foundation

struct ArchPlannerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "arch-planner",
        abstract: "Architecture-driven planning and implementation",
        subcommands: [
            ArchPlannerCreateCommand.self,
            ArchPlannerDeleteCommand.self,
            ArchPlannerExecuteCommand.self,
            ArchPlannerGuidelinesCommand.self,
            ArchPlannerInspectCommand.self,
            ArchPlannerReportCommand.self,
            ArchPlannerScoreCommand.self,
            ArchPlannerUpdateCommand.self,
        ]
    )

    @Option(help: "Data directory path (overrides app settings)")
    var dataPath: String?
}
