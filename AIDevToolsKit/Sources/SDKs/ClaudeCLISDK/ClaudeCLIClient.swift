import Foundation
import CLISDK

public struct ClaudeCLIClient: Sendable {

    private let client: CLIClient

    public init(client: CLIClient = CLIClient()) {
        self.client = client
    }

    public func run(
        command: Claude,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        onOutput: (@Sendable (StreamOutput) -> Void)? = nil
    ) async throws -> ExecutionResult {
        var env = environment ?? ProcessInfo.processInfo.environment
        env[ClaudeEnvironmentKey.claudeCode] = ""
        let home = env["HOME"] ?? "/Users/\(NSUserName())"
        let additionalPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin"
        ]
        if let existingPath = env["PATH"] {
            env["PATH"] = additionalPaths.joined(separator: ":") + ":" + existingPath
        } else {
            env["PATH"] = additionalPaths.joined(separator: ":") + ":/usr/bin:/bin"
        }

        let claudePath = Self.resolveClaudePath()

        var outputStream: CLIOutputStream?
        var outputTask: Task<Void, Never>?
        if let onOutput {
            let stream = CLIOutputStream()
            outputStream = stream
            outputTask = Task {
                for await item in await stream.makeStream() {
                    onOutput(item)
                }
            }
        }

        let result = try await client.execute(
            command: claudePath,
            arguments: command.commandArguments,
            workingDirectory: workingDirectory,
            environment: env,
            printCommand: false,
            output: outputStream
        )

        if let outputStream {
            await outputStream.finishAll()
        }
        outputTask?.cancel()

        return result
    }

    public func run(
        command: Claude,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        onFormattedOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> ExecutionResult {
        let formatter = ClaudeStreamFormatter()
        return try await run(
            command: command,
            workingDirectory: workingDirectory,
            environment: environment,
            onOutput: onFormattedOutput.map { callback -> @Sendable (StreamOutput) -> Void in
                { item in
                    switch item {
                    case .stdout(_, let text):
                        let formatted = formatter.format(text)
                        if !formatted.isEmpty {
                            callback(formatted)
                        }
                    case .stderr(_, let text):
                        let nonJSON = text.components(separatedBy: "\n")
                            .filter { line in
                                let trimmed = line.trimmingCharacters(in: .whitespaces)
                                return !trimmed.isEmpty && !trimmed.hasPrefix("{")
                            }
                            .joined(separator: "\n")
                        if !nonJSON.isEmpty {
                            callback(nonJSON)
                        }
                    default:
                        break
                    }
                }
            }
        )
    }

    public func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        command: Claude,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        onFormattedOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> ClaudeStructuredOutput<T> {
        let executionResult = try await run(
            command: command,
            workingDirectory: workingDirectory,
            environment: environment,
            onFormattedOutput: onFormattedOutput
        )
        let parser = ClaudeStructuredOutputParser()
        return try parser.parse(type, from: executionResult.stdout)
    }

    private static func resolveClaudePath() -> String {
        let preferredPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/claude").path
        if FileManager.default.fileExists(atPath: preferredPath) {
            return preferredPath
        }
        return "claude"
    }
}
