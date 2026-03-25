import ArgumentParser
import DataPathsService
import Foundation

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Show configuration",
        subcommands: [ShowCommand.self],
        defaultSubcommand: ShowCommand.self
    )

    struct ShowCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Show resolved configuration values"
        )

        func run() throws {
            let resolved = ResolveDataPathUseCase().resolve()
            let sourceLabel: String
            switch resolved.source {
            case .explicit:
                sourceLabel = "CLI argument"
            case .userDefaults:
                sourceLabel = "app settings"
            case .defaultPath:
                sourceLabel = "default"
            }
            print("Data path: \(resolved.path.path(percentEncoded: false)) (\(sourceLabel))")
        }
    }
}
