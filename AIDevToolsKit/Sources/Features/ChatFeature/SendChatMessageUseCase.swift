import AIOutputSDK
import Foundation
import UseCaseSDK

public struct SendChatMessageUseCase: UseCase {

    public struct Options: Sendable {
        public let images: [ImageAttachment]
        public let mcpConfigPath: String?
        public let message: String
        public let sessionId: String?
        public let systemPrompt: String?
        public let workingDirectory: String?

        public init(
            message: String,
            workingDirectory: String? = nil,
            sessionId: String? = nil,
            images: [ImageAttachment] = [],
            mcpConfigPath: String? = nil,
            systemPrompt: String? = nil
        ) {
            self.images = images
            self.mcpConfigPath = mcpConfigPath
            self.message = message
            self.sessionId = sessionId
            self.systemPrompt = systemPrompt
            self.workingDirectory = workingDirectory
        }
    }

    public struct Result: Sendable {
        public let exitCode: Int32
        public let fullText: String
        public let sessionId: String?
        public let stderr: String

        public init(exitCode: Int32, fullText: String, sessionId: String?, stderr: String = "") {
            self.exitCode = exitCode
            self.fullText = fullText
            self.sessionId = sessionId
            self.stderr = stderr
        }
    }

    public enum Progress: Sendable {
        case completed(fullText: String)
        case streamEvent(AIStreamEvent)
    }

    private let client: any AIClient

    public init(client: any AIClient) {
        self.client = client
    }

    public func run(
        _ options: Options,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> Result {
        var promptText = options.message
        var tempDirectory: URL?

        if !options.images.isEmpty {
            let (updatedPrompt, tempDir) = prepareImagePrompt(
                basePrompt: promptText,
                images: options.images
            )
            promptText = updatedPrompt
            tempDirectory = tempDir
        }

        defer {
            if let tempDirectory {
                try? FileManager.default.removeItem(at: tempDirectory)
            }
        }

        let aiOptions = AIClientOptions(
            dangerouslySkipPermissions: true,
            mcpConfigPath: options.mcpConfigPath,
            sessionId: options.sessionId,
            systemPrompt: options.systemPrompt,
            workingDirectory: options.workingDirectory
        )

        let result = try await client.run(
            prompt: promptText,
            options: aiOptions,
            onOutput: nil,
            onStreamEvent: { event in
                onProgress?(.streamEvent(event))
            }
        )

        onProgress?(.completed(fullText: result.stdout))
        return Result(
            exitCode: result.exitCode,
            fullText: result.stdout,
            sessionId: result.sessionId,
            stderr: result.stderr
        )
    }

    private func prepareImagePrompt(
        basePrompt: String,
        images: [ImageAttachment]
    ) -> (prompt: String, tempDir: URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-images-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var imagePaths: [String] = []
        for (index, imageAttachment) in images.enumerated() {
            if let imageData = Data(base64Encoded: imageAttachment.base64Data) {
                let filename = "image-\(index).png"
                let filePath = tempDir.appendingPathComponent(filename)
                try? imageData.write(to: filePath)
                imagePaths.append(filePath.path)
            }
        }

        guard !imagePaths.isEmpty else { return (basePrompt, tempDir) }

        var prompt = basePrompt
        prompt += "\n\nI've attached \(imagePaths.count) image(s). Please analyze them:\n"
        for (index, path) in imagePaths.enumerated() {
            prompt += "\nImage \(index + 1): \(path)"
        }
        prompt += "\n\nPlease use your Read tool to view these images and incorporate them into your response."
        return (prompt, tempDir)
    }
}
