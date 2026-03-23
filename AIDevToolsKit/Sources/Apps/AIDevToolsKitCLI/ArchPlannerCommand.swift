import ArgumentParser
import ArchitecturePlannerService
import DataPathsService
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

    @Option(help: "Data directory path (default: ~/Desktop/ai-dev-tools)")
    var dataPath: String?

    static func makeStore(dataPath: String?, repoName: String) throws -> ArchitecturePlannerStore {
        let service = try DataPathsService.fromCLI(dataPath: dataPath)
        let archDir = try service.path(for: "architecture-planner", subdirectory: repoName)
        return try ArchitecturePlannerStore(directoryURL: archDir)
    }
}
