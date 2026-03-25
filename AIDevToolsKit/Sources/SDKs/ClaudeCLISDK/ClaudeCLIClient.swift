import CLISDK
import ConcurrencySDK
import Foundation
import Logging

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

    private static let inactivityTimeout: TimeInterval = 480
    private static let logger = Logger(label: "ClaudeCLIClient")

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
        maxTimeoutRetries: Int = 1,
        onFormattedOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> ClaudeStructuredOutput<T> {
        let formatter = ClaudeStreamFormatter()
        let stdoutCapture = StdoutAccumulator()
        let parser = ClaudeStructuredOutputParser()
        var currentCommand = command

        // stream-json + print mode requires verbose — auto-enable to avoid silent CLI errors
        if currentCommand.outputFormat == ClaudeOutputFormat.streamJSON.rawValue
            && currentCommand.printMode
            && !currentCommand.verbose {
            currentCommand.verbose = true
        }
        var retryCount = 0

        while true {
            do {
                let result = try await run(
                    command: currentCommand,
                    workingDirectory: workingDirectory,
                    environment: environment,
                    onOutput: Self.outputHandler(
                        formatter: formatter,
                        stdoutCapture: stdoutCapture,
                        onFormattedOutput: onFormattedOutput
                    )
                )
                return try parser.parse(type, from: result)
            } catch let error as ClaudeCLIError {
                guard case .inactivityTimeout = error,
                      retryCount < maxTimeoutRetries,
                      let sessionId = Self.extractSessionId(from: stdoutCapture.content) else {
                    throw error
                }
                retryCount += 1
                currentCommand = Self.resumeCommand(from: command, sessionId: sessionId)
            }
        }
    }

    // MARK: - Timeout Retry Helpers

    private static func outputHandler(
        formatter: ClaudeStreamFormatter,
        stdoutCapture: StdoutAccumulator,
        onFormattedOutput: (@Sendable (String) -> Void)?
    ) -> @Sendable (StreamOutput) -> Void {
        { item in
            switch item {
            case .stdout(_, let text):
                stdoutCapture.append(text)
                if let onFormattedOutput {
                    let formatted = formatter.format(text)
                    if !formatted.isEmpty { onFormattedOutput(formatted) }
                }
            case .stderr(_, let text):
                if let onFormattedOutput {
                    let nonJSON = text.components(separatedBy: "\n")
                        .filter { line in
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            return !trimmed.isEmpty && !trimmed.hasPrefix("{")
                        }
                        .joined(separator: "\n")
                    if !nonJSON.isEmpty { onFormattedOutput(nonJSON) }
                }
            default:
                break
            }
        }
    }

    static func extractSessionId(from stdout: String) -> String? {
        let decoder = JSONDecoder()
        for line in stdout.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }

            let envelope: ClaudeEventEnvelope
            do {
                envelope = try decoder.decode(ClaudeEventEnvelope.self, from: data)
            } catch {
                logger.error("Failed to decode event envelope: \(error.localizedDescription)", metadata: [
                    "line": "\(trimmed.prefix(200))"
                ])
                continue
            }

            guard envelope.type == ClaudeEventType.system else { continue }

            do {
                let event = try decoder.decode(ClaudeSystemEvent.self, from: data)
                guard let sessionId = event.sessionId else {
                    logger.error("System event missing session_id", metadata: [
                        "line": "\(trimmed.prefix(200))"
                    ])
                    continue
                }
                return sessionId
            } catch {
                logger.error("Failed to decode system event: \(error.localizedDescription)", metadata: [
                    "line": "\(trimmed.prefix(200))"
                ])
                continue
            }
        }
        return nil
    }

    private static func resumeCommand(from original: Claude, sessionId: String) -> Claude {
        var command = Claude(prompt: "Continue where you left off.")
        command.resume = sessionId
        command.dangerouslySkipPermissions = original.dangerouslySkipPermissions
        command.jsonSchema = original.jsonSchema
        command.model = original.model
        command.outputFormat = original.outputFormat
        command.printMode = original.printMode
        command.verbose = original.verbose
        return command
    }

    // MARK: - Path Resolution

    private static func resolveClaudePath() -> String {
        let preferredPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/claude").path
        if FileManager.default.fileExists(atPath: preferredPath) {
            return preferredPath
        }
        return "claude"
    }
}

final class StdoutAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    var content: String {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func append(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        buffer += text
    }
}
