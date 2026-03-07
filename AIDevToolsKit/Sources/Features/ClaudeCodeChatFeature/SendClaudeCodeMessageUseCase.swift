import ClaudeCodeChatService
import ClaudeCLISDK
import Foundation

public struct SendClaudeCodeMessageUseCase: Sendable {

    public struct Options: Sendable {
        public let message: String
        public let workingDirectory: String
        public let sessionId: String?
        public let images: [ImageAttachment]

        public init(
            message: String,
            workingDirectory: String,
            sessionId: String? = nil,
            images: [ImageAttachment] = []
        ) {
            self.message = message
            self.workingDirectory = workingDirectory
            self.sessionId = sessionId
            self.images = images
        }
    }

    public enum Progress: Sendable {
        case textDelta(String)
        case completed(fullText: String)
    }

    private let claudeClient: ClaudeCLIClient

    public init(claudeClient: ClaudeCLIClient = ClaudeCLIClient()) {
        self.claudeClient = claudeClient
    }

    public func run(
        _ options: Options,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> String {
        var command = Claude(prompt: options.message)
        command.dangerouslySkipPermissions = true
        command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
        command.verbose = true
        if let sessionId = options.sessionId {
            command.resume = sessionId
        }

        actor TextAccumulator {
            var text = ""
            func append(_ chunk: String) { text += chunk }
        }
        let accumulator = TextAccumulator()

        let result = try await claudeClient.run(
            command: command,
            workingDirectory: options.workingDirectory,
            onFormattedOutput: { @Sendable chunk in
                Task { await accumulator.append(chunk) }
                onProgress?(.textDelta(chunk))
            }
        )

        if result.exitCode != 0 {
            throw ClaudeCodeChatError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
        }

        let fullText = await accumulator.text
        onProgress?(.completed(fullText: fullText))
        return fullText
    }
}

public enum ClaudeCodeChatError: Error, LocalizedError {
    case commandFailed(exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let exitCode, let stderr):
            return "Claude CLI failed (exit code \(exitCode)): \(stderr)"
        }
    }
}
