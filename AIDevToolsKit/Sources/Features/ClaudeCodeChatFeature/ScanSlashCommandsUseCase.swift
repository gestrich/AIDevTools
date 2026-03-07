import Foundation
import SlashCommandSDK

public struct ScanSlashCommandsUseCase: Sendable {

    public struct Options: Sendable {
        public let workingDirectory: String
        public let query: String?

        public init(workingDirectory: String, query: String? = nil) {
            self.workingDirectory = workingDirectory
            self.query = query
        }
    }

    private let scanner: SlashCommandScanner

    public init(scanner: SlashCommandScanner = SlashCommandScanner()) {
        self.scanner = scanner
    }

    public func run(_ options: Options) -> [SlashCommand] {
        let commands = scanner.scanCommands(workingDirectory: options.workingDirectory)
        if let query = options.query, !query.isEmpty {
            return scanner.filterCommands(commands, query: query)
        }
        return commands
    }
}
