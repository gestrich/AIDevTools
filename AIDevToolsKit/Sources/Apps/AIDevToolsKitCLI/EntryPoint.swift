import ArgumentParser
import ClaudeChainCLI
import EnvironmentSDK
import Foundation
import Logging
import LoggingSDK

@main
struct AIDevToolsKit: AsyncParsableCommand {
    nonisolated(unsafe) static var bootstrapped = false

    static let configuration = CommandConfiguration(
        commandName: "ai-dev-tools-kit",
        abstract: "Developer tools for AI-assisted workflows",
        subcommands: [ArchPlannerCommand.self, ChatCommand.self, ClaudeChainCLI.self, ClearArtifactsCommand.self, ConfigCommand.self, CredentialsCommand.self, ListCasesCommand.self, LogsCommand.self, MarkdownPlannerCommand.self, MCPCommand.self, PRRadarCommand.self, ReposCommand.self, RunEvalsCommand.self, ShowOutputCommand.self, SkillsCommand.self]
    )

    @Option(name: .long, help: "Log level: trace, debug, info, notice, warning, error, critical")
    var logLevel: Logger.Level = .info

    mutating func validate() throws {
        guard !Self.bootstrapped else { return }
        AIDevToolsLogging.bootstrap(logLevel: logLevel)
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

extension Logger.Level: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}
