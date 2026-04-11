import ArgumentParser
import ClaudeChainCLI
import DataPathsService
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
        subcommands: subcommandTypes
    )

    static func main() async {
        writeMCPConfig()
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
            ChatCommand.self, ClaudeChainCLI.self, ClearArtifactsCommand.self, ConfigCommand.self, CredentialsCommand.self, ListCasesCommand.self, LogsCommand.self, MCPCommand.self, PlanCommand.self, PRRadarCommand.self, ReposCommand.self, RunEvalsCommand.self, ShowOutputCommand.self, SkillsCommand.self, SweepCommand.self, WorktreeCommand.self,
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

    // Fallback writer — the Mac app is the primary MCP config writer when the repo path is configured in Settings.
    private static func writeMCPConfig() {
        let arg0 = ProcessInfo.processInfo.arguments[0]
        let executableURL: URL
        if arg0.hasPrefix("/") {
            executableURL = URL(fileURLWithPath: arg0).standardizedFileURL
        } else {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            executableURL = URL(fileURLWithPath: arg0, relativeTo: cwd).standardizedFileURL
        }
        let config = """
        {
          "mcpServers": {
            "ai-dev-tools-kit": {
              "command": "\(executableURL.path)",
              "args": ["mcp"]
            }
          }
        }
        """
        let fileURL = DataPathsService.mcpConfigFileURL
        // Best-effort write; failure here is non-fatal since the Mac app is the primary writer.
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? config.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

extension Logger.Level: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}
