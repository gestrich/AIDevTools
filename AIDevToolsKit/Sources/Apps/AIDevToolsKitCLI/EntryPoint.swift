import ArgumentParser
import EnvironmentSDK
import Foundation
import LoggingSDK

@main
struct AIDevToolsKit: AsyncParsableCommand {
    nonisolated(unsafe) static var bootstrapped = false

    static let configuration = CommandConfiguration(
        commandName: "ai-dev-tools-kit",
        abstract: "Developer tools for AI-assisted workflows",
        subcommands: [ArchPlannerCommand.self, ChatCommand.self, ClearArtifactsCommand.self, ConfigCommand.self, ListCasesCommand.self, MarkdownPlannerCommand.self, ReposCommand.self, RunEvalsCommand.self, ShowOutputCommand.self, SkillsCommand.self]
    )

    mutating func validate() throws {
        guard !Self.bootstrapped else { return }
        AIDevToolsLogging.bootstrap()
        loadDotEnv()
        Self.bootstrapped = true
    }

    private func loadDotEnv() {
        for (key, value) in DotEnvironmentLoader.loadDotEnv() {
            if ProcessInfo.processInfo.environment[key] == nil {
                setenv(key, value, 0)
            }
        }
    }
}
