import Foundation
import CLISDK

public struct CodexCLIClient: Sendable {

    private let client: CLIClient

    public init(client: CLIClient = CLIClient()) {
        self.client = client
    }

    public func run(
        command: Codex.Exec,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        onOutput: (@Sendable (StreamOutput) -> Void)? = nil
    ) async throws -> ExecutionResult {
        try await executeCodex(
            arguments: command.commandArguments,
            workingDirectory: workingDirectory,
            environment: environment,
            onOutput: onOutput
        )
    }

    public func run(
        command: Codex.Exec,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        onFormattedOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> ExecutionResult {
        try await runFormatted(
            arguments: command.commandArguments,
            workingDirectory: workingDirectory,
            environment: environment,
            onFormattedOutput: onFormattedOutput
        )
    }

    public func run(
        command: Codex.Exec.Resume,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        onFormattedOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> ExecutionResult {
        try await runFormatted(
            arguments: command.commandArguments,
            workingDirectory: workingDirectory,
            environment: environment,
            onFormattedOutput: onFormattedOutput
        )
    }

    // MARK: - Internal

    private func runFormatted(
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String]?,
        onFormattedOutput: (@Sendable (String) -> Void)?
    ) async throws -> ExecutionResult {
        let formatter = CodexStreamFormatter()
        return try await executeCodex(
            arguments: arguments,
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
                        let formatted = formatter.format(text)
                        if !formatted.isEmpty {
                            callback(formatted)
                        } else {
                            let nonJSON = text.components(separatedBy: "\n")
                                .filter { line in
                                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                                    return !trimmed.isEmpty && !trimmed.hasPrefix("{")
                                }
                                .joined(separator: "\n")
                            if !nonJSON.isEmpty {
                                callback(nonJSON)
                            }
                        }
                    default:
                        break
                    }
                }
            }
        )
    }

    private func executeCodex(
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String]?,
        onOutput: (@Sendable (StreamOutput) -> Void)?
    ) async throws -> ExecutionResult {
        var env = environment ?? ProcessInfo.processInfo.environment
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

        let codexPath = Self.resolveCodexPath()

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
            command: codexPath,
            arguments: arguments,
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

    private static func resolveCodexPath() -> String {
        let preferredPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/codex").path
        if FileManager.default.fileExists(atPath: preferredPath) {
            return preferredPath
        }
        return "codex"
    }
}
