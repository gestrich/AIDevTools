import AIOutputSDK
import Foundation
import Observation

public struct QueuedMessage: Identifiable, Sendable {
    public let id: UUID
    public let content: String
    public let images: [ImageAttachment]
    public let timestamp: Date

    public init(id: UUID = UUID(), content: String, images: [ImageAttachment] = [], timestamp: Date = Date()) {
        self.id = id
        self.content = content
        self.images = images
        self.timestamp = timestamp
    }
}

@Observable
@MainActor
public final class ChatManager {
    public private(set) var messages: [ChatMessage] = []
    public private(set) var isProcessing: Bool = false
    public private(set) var isLoadingHistory: Bool = false
    public private(set) var messageQueue: [QueuedMessage] = []
    public let providerDisplayName: String
    public let settings: ChatSettings

    private let client: any AIClient
    private var sessionId: String?
    public private(set) var workingDirectory: String
    private var currentTask: Task<Void, Never>?
    private var hasStartedSession: Bool = false

    public var currentSessionId: String? { sessionId }
    public var providerName: String { client.name }
    public var supportsSessionHistory: Bool { client is SessionListable }

    public init(client: any AIClient, workingDirectory: String?, settings: ChatSettings = ChatSettings()) {
        self.client = client
        self.settings = settings
        self.providerDisplayName = client.displayName

        let rawWorkingDir = workingDirectory ?? FileManager.default.currentDirectoryPath
        self.workingDirectory = Self.resolveSymlinks(in: rawWorkingDir)

        if settings.resumeLastSession, let listable = client as? SessionListable {
            self.isLoadingHistory = true
            let workDir = self.workingDirectory
            Task {
                let sessions = await listable.listSessions(workingDirectory: workDir)
                if let mostRecent = sessions.first {
                    let sessionMessages = await listable.loadSessionMessages(sessionId: mostRecent.id, workingDirectory: workDir)
                    self.messages = sessionMessages.map { ChatMessage(role: $0.role == .user ? .user : .assistant, content: $0.content, isComplete: true) }
                    self.sessionId = mostRecent.id
                    self.hasStartedSession = true
                }
                self.isLoadingHistory = false
            }
        }
    }

    // MARK: - Public API

    public nonisolated func sendMessage(_ content: String, images: [ImageAttachment] = []) async {
        guard !content.isEmpty || !images.isEmpty else { return }

        let currentlyProcessing = await MainActor.run { isProcessing }

        if currentlyProcessing {
            await MainActor.run {
                let queuedMessage = QueuedMessage(content: content, images: images)
                messageQueue.append(queuedMessage)
            }
            return
        }

        await sendMessageInternal(content, images: images)
    }

    public func startNewConversation() {
        messages.removeAll()
        sessionId = nil
        hasStartedSession = false
        messageQueue.removeAll()
    }

    public func cancelCurrentRequest() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
    }

    public func clearMessages() {
        messages.removeAll()
    }

    public func removeQueuedMessage(id: UUID) {
        messageQueue.removeAll { $0.id == id }
    }

    public func clearQueue() {
        messageQueue.removeAll()
    }

    // MARK: - Session Management

    public func listSessions() async -> [ChatSession] {
        guard let listable = client as? SessionListable else { return [] }
        return await listable.listSessions(workingDirectory: workingDirectory)
    }

    public func resumeSession(_ sessionId: String) async {
        self.messages = []
        self.sessionId = sessionId
        self.hasStartedSession = true
        self.isLoadingHistory = true

        guard let listable = client as? SessionListable else {
            self.isLoadingHistory = false
            return
        }

        let sessionMessages = await listable.loadSessionMessages(sessionId: sessionId, workingDirectory: workingDirectory)
        self.messages = sessionMessages.map { ChatMessage(role: $0.role == .user ? .user : .assistant, content: $0.content, isComplete: true) }
        self.isLoadingHistory = false
    }

    public func setWorkingDirectory(_ path: String) async {
        let resolvedPath = Self.resolveSymlinks(in: path)
        guard resolvedPath != workingDirectory else { return }

        self.workingDirectory = resolvedPath
        self.messages = []
        self.sessionId = nil
        self.hasStartedSession = false

        if settings.resumeLastSession, let listable = client as? SessionListable {
            self.isLoadingHistory = true
            let sessions = await listable.listSessions(workingDirectory: resolvedPath)
            guard self.workingDirectory == resolvedPath else { return }
            if let mostRecent = sessions.first {
                let sessionMessages = await listable.loadSessionMessages(sessionId: mostRecent.id, workingDirectory: resolvedPath)
                guard self.workingDirectory == resolvedPath else { return }
                self.messages = sessionMessages.map { ChatMessage(role: $0.role == .user ? .user : .assistant, content: $0.content, isComplete: true) }
                self.sessionId = mostRecent.id
                self.hasStartedSession = true
            }
            self.isLoadingHistory = false
        }
    }

    // MARK: - Internal

    private nonisolated func sendMessageInternal(_ content: String, images: [ImageAttachment] = []) async {
        let userMessage = ChatMessage(role: .user, content: content, images: images, isComplete: true)
        await MainActor.run {
            messages.append(userMessage)
            isProcessing = true
        }

        let resumeId = await MainActor.run {
            settings.resumeLastSession && hasStartedSession ? sessionId : nil
        }
        let workingDir = await MainActor.run { workingDirectory }

        var promptText = content
        var imagePaths: [String] = []

        if !images.isEmpty {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("chat-images-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            for (index, imageAttachment) in images.enumerated() {
                if let imageData = Data(base64Encoded: imageAttachment.base64Data) {
                    let filename = "image-\(index).png"
                    let filePath = tempDir.appendingPathComponent(filename)
                    try? imageData.write(to: filePath)
                    imagePaths.append(filePath.path)
                }
            }

            if !imagePaths.isEmpty {
                var imagePromptPart = "\n\nI've attached \(imagePaths.count) image(s). Please analyze them:\n"
                for (index, path) in imagePaths.enumerated() {
                    imagePromptPart += "\nImage \(index + 1): \(path)"
                }
                imagePromptPart += "\n\nPlease use your Read tool to view these images and incorporate them into your response."
                promptText += imagePromptPart
            }
        }

        let assistantMessageId = UUID()
        let placeholderMessage = ChatMessage(
            id: assistantMessageId,
            role: .assistant,
            content: "",
            timestamp: Date()
        )

        await MainActor.run {
            messages.append(placeholderMessage)
        }

        actor StreamAccumulator {
            var content = ""

            func append(_ chunk: String) -> String {
                content += chunk
                return content
            }
        }

        let accumulator = StreamAccumulator()

        let options = AIClientOptions(
            dangerouslySkipPermissions: true,
            sessionId: resumeId,
            workingDirectory: workingDir
        )

        do {
            let result = try await client.run(
                prompt: promptText,
                options: options,
                onOutput: { @Sendable chunk in
                    Task {
                        let updatedContent = await accumulator.append(chunk)
                        await MainActor.run { [updatedContent] in
                            if let index = self.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                                self.messages[index] = ChatMessage(
                                    id: assistantMessageId,
                                    role: .assistant,
                                    content: updatedContent,
                                    timestamp: self.messages[index].timestamp
                                )
                            }
                        }
                    }
                }
            )

            await MainActor.run {
                if result.exitCode == 0 {
                    hasStartedSession = true
                    if let newSessionId = result.sessionId {
                        sessionId = newSessionId
                    }
                }

                if let index = messages.firstIndex(where: { $0.id == assistantMessageId }) {
                    let existing = messages[index]

                    if result.exitCode != 0 {
                        let errorMessage: String
                        if result.exitCode == 130 || result.exitCode == 143 {
                            errorMessage = "Request interrupted by user"
                        } else {
                            errorMessage = "Error running \(providerDisplayName) (exit code \(result.exitCode))\n\(result.stderr)"
                        }
                        messages[index] = ChatMessage(
                            id: assistantMessageId,
                            role: .assistant,
                            content: errorMessage,
                            timestamp: existing.timestamp,
                            isComplete: true
                        )
                    } else {
                        messages[index] = ChatMessage(
                            id: existing.id,
                            role: existing.role,
                            content: existing.content,
                            images: existing.images,
                            timestamp: existing.timestamp,
                            isComplete: true
                        )
                    }
                }
                isProcessing = false
            }
        } catch {
            await MainActor.run {
                if let index = messages.firstIndex(where: { $0.id == assistantMessageId }) {
                    messages[index] = ChatMessage(
                        id: assistantMessageId,
                        role: .assistant,
                        content: "Error: \(error.localizedDescription)",
                        timestamp: messages[index].timestamp,
                        isComplete: true
                    )
                }
                isProcessing = false
            }
        }

        if !imagePaths.isEmpty, let firstPath = imagePaths.first {
            let tempDir = URL(fileURLWithPath: firstPath).deletingLastPathComponent()
            try? FileManager.default.removeItem(at: tempDir)
        }

        await processNextQueuedMessage()
    }

    private nonisolated func processNextQueuedMessage() async {
        let nextMessage = await MainActor.run { messageQueue.first }

        guard let queuedMessage = nextMessage else { return }

        _ = await MainActor.run {
            messageQueue.removeFirst()
        }

        await sendMessageInternal(queuedMessage.content, images: queuedMessage.images)
    }

    // MARK: - Helpers

    private static func resolveSymlinks(in path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(path, &buffer) != nil {
            return String(cString: buffer)
        }

        let url = URL(fileURLWithPath: path)
        let components = url.pathComponents
        var resolvedComponents: [String] = []

        for component in components {
            resolvedComponents.append(component)
            let partialPath = resolvedComponents.joined(separator: "/").replacingOccurrences(of: "//", with: "/")
            if realpath(partialPath, &buffer) != nil {
                let resolved = String(cString: buffer)
                resolvedComponents = URL(fileURLWithPath: resolved).pathComponents
            }
        }

        return resolvedComponents.joined(separator: "/").replacingOccurrences(of: "//", with: "/")
    }
}
