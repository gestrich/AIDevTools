import AIOutputSDK
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

    public struct Result: Sendable {
        public let fullText: String
        public let sessionId: String?
    }

    public enum Progress: Sendable {
        case textDelta(String)
        case completed(fullText: String)
    }

    private let client: any AIClient

    public init(client: any AIClient) {
        self.client = client
    }

    public func run(
        _ options: Options,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> Result {
        let aiOptions = AIClientOptions(
            dangerouslySkipPermissions: true,
            sessionId: options.sessionId,
            workingDirectory: options.workingDirectory
        )

        let result = try await client.run(
            prompt: options.message,
            options: aiOptions,
            onOutput: { chunk in
                onProgress?(.textDelta(chunk))
            }
        )

        if result.exitCode != 0 {
            throw ClaudeCodeChatError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
        }

        onProgress?(.completed(fullText: result.stdout))
        return Result(fullText: result.stdout, sessionId: result.sessionId)
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
