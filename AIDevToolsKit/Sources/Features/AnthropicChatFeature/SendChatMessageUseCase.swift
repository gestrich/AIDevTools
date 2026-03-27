import AIOutputSDK
import Foundation

public struct SendChatMessageUseCase: Sendable {

    public struct Options: Sendable {
        public let message: String
        public let sessionId: String?
        public let systemPrompt: String?

        public init(
            message: String,
            sessionId: String? = nil,
            systemPrompt: String? = nil
        ) {
            self.message = message
            self.sessionId = sessionId
            self.systemPrompt = systemPrompt
        }
    }

    public struct Result: Sendable {
        public let fullText: String
        public let sessionId: String?
    }

    public enum Progress: Sendable {
        case completed(fullText: String)
        case textDelta(String)
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
            sessionId: options.sessionId,
            systemPrompt: options.systemPrompt
        )

        let result = try await client.run(
            prompt: options.message,
            options: aiOptions,
            onOutput: { chunk in
                onProgress?(.textDelta(chunk))
            }
        )

        onProgress?(.completed(fullText: result.stdout))
        return Result(fullText: result.stdout, sessionId: result.sessionId)
    }
}
