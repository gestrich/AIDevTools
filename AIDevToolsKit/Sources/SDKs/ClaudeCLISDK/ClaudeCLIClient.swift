import ConcurrencySDK
import Foundation
import CLISDK

public enum ClaudeCLIError: Error, LocalizedError {
    case inactivityTimeout(seconds: Int)

    public var errorDescription: String? {
        switch self {
        case .inactivityTimeout(let seconds):
            return "No output from Claude CLI for \(seconds) seconds"
        }
    }
}

public struct ClaudeCLIClient: Sendable {

    private static let inactivityTimeout: TimeInterval = 120

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

        let timeoutError = ClaudeCLIError.inactivityTimeout(seconds: Int(Self.inactivityTimeout))
        let watchdog = InactivityWatchdog(timeout: Self.inactivityTimeout, onTimeout: {})
        var timedOut = false

        let stream = CLIOutputStream()
        let outputStream: CLIOutputStream = stream
        let outputTask = Task {
            for await item in await stream.makeStream() {
                await watchdog.recordActivity()
                onOutput?(item)
            }
        }

        await watchdog.start()
        let result: ExecutionResult
        do {
            result = try await withThrowingTaskGroup(of: ExecutionResult.self) { group in
                group.addTask {
                    try await client.execute(
                        command: claudePath,
                        arguments: command.commandArguments,
                        workingDirectory: workingDirectory,
                        environment: env,
                        printCommand: false,
                        output: outputStream
                    )
                }
                group.addTask {
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(15))
                        let elapsed = await watchdog.timeSinceLastActivity()
                        if elapsed >= Self.inactivityTimeout {
                            timedOut = true
                            throw timeoutError
                        }
                    }
                    throw CancellationError()
                }
                let value = try await group.next()!
                group.cancelAll()
                return value
            }
        } catch {
            await watchdog.cancel()
            outputTask.cancel()
            if timedOut {
                throw timeoutError
            }
            throw error
        }

        await watchdog.cancel()
        await outputStream.finishAll()
        outputTask.cancel()

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
