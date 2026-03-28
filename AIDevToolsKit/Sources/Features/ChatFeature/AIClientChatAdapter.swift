import AIOutputSDK
import Foundation

public final class AIClientChatAdapter: @unchecked Sendable, ChatProvider {

    private let client: any AIClient
    private let sessionLister: (any SessionListable)?
    private let _supportsSessionHistory: Bool

    public let displayName: String
    public let name: String
    public var supportsSessionHistory: Bool { _supportsSessionHistory }

    public init(client: any AIClient & SessionListable) {
        self.client = client
        self.sessionLister = client
        self._supportsSessionHistory = true
        self.displayName = client.displayName
        self.name = client.name
    }

    public init(client: any AIClient) {
        self.client = client
        self.sessionLister = nil
        self._supportsSessionHistory = false
        self.displayName = client.displayName
        self.name = client.name
    }

    // MARK: - ChatProvider

    public func sendMessage(
        _ message: String,
        images: [ImageAttachment],
        options: ChatProviderOptions,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> ChatProviderResult {
        var promptText = message
        var tempDirectory: URL?

        if !images.isEmpty {
            let (updatedPrompt, tempDir) = Self.prepareImagePrompt(
                basePrompt: promptText,
                images: images
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
            dangerouslySkipPermissions: options.dangerouslySkipPermissions,
            model: options.model,
            sessionId: options.sessionId,
            systemPrompt: options.systemPrompt,
            workingDirectory: options.workingDirectory
        )

        let result = try await client.run(
            prompt: promptText,
            options: aiOptions,
            onOutput: nil,
            onStreamEvent: onStreamEvent
        )

        return ChatProviderResult(content: result.stdout, sessionId: result.sessionId)
    }

    public func cancel() async {}

    public func getSessionDetails(sessionId: String, summary: String, lastModified: Date, workingDirectory: String) -> SessionDetails? {
        sessionLister?.getSessionDetails(sessionId: sessionId, summary: summary, lastModified: lastModified, workingDirectory: workingDirectory)
    }

    public func listSessions(workingDirectory: String) async -> [ChatSession] {
        await sessionLister?.listSessions(workingDirectory: workingDirectory) ?? []
    }

    public func loadSessionMessages(sessionId: String, workingDirectory: String) async -> [ChatSessionMessage] {
        await sessionLister?.loadSessionMessages(sessionId: sessionId, workingDirectory: workingDirectory) ?? []
    }

    // MARK: - Factory

    public static func make(from client: any AIClient) -> AIClientChatAdapter {
        if let sessionListable = client as? (any AIClient & SessionListable) {
            return AIClientChatAdapter(client: sessionListable)
        }
        return AIClientChatAdapter(client: client)
    }

    // MARK: - Image Handling

    private static func prepareImagePrompt(
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
