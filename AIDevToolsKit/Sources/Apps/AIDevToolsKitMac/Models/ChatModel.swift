import AIOutputSDK
import ChatFeature
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
public final class ChatModel {
    public private(set) var messages: [ChatMessage] = []
    public private(set) var isProcessing: Bool = false
    public private(set) var isLoadingHistory: Bool = false
    public private(set) var messageQueue: [QueuedMessage] = []
    public let providerDisplayName: String
    public let settings: ChatSettings
    public private(set) var workingDirectory: String
    public private(set) var currentStreamingMessageId: UUID?

    public var currentSessionId: String? { sessionId }
    public var providerName: String { provider.name }
    public var supportsSessionHistory: Bool { provider.supportsSessionHistory }

    private let provider: any ChatProvider
    private let systemPrompt: String?
    private var sessionId: String?
    private var currentTask: Task<Void, Never>?
    private var hasStartedSession: Bool = false

    public init(
        provider: any ChatProvider,
        workingDirectory: String?,
        settings: ChatSettings = ChatSettings(),
        systemPrompt: String? = nil
    ) {
        self.provider = provider
        self.settings = settings
        self.providerDisplayName = provider.displayName
        self.systemPrompt = systemPrompt

        let rawWorkingDir = workingDirectory ?? FileManager.default.currentDirectoryPath
        self.workingDirectory = Self.resolveSymlinks(in: rawWorkingDir)

        if settings.resumeLastSession, provider.supportsSessionHistory {
            self.isLoadingHistory = true
            let workDir = self.workingDirectory
            Task {
                let sessions = await provider.listSessions(workingDirectory: workDir)
                if let mostRecent = sessions.first {
                    let sessionMessages = await provider.loadSessionMessages(sessionId: mostRecent.id, workingDirectory: workDir)
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

    // MARK: - Programmatic Message Injection

    public func appendStatusMessage(_ content: String) {
        messages.append(ChatMessage(role: .assistant, content: content, isComplete: true))
    }

    public func beginStreamingMessage() {
        let id = UUID()
        messages.append(ChatMessage(id: id, role: .assistant, contentBlocks: [], timestamp: Date()))
        currentStreamingMessageId = id
    }

    public func appendTextToCurrentStreamingMessage(_ text: String) {
        guard let id = currentStreamingMessageId,
              let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let existing = messages[index]
        var blocks = existing.contentBlocks
        if case .text(let prev) = blocks.last {
            blocks[blocks.count - 1] = .text(prev + text)
        } else {
            blocks.append(.text(text))
        }
        messages[index] = ChatMessage(
            id: existing.id,
            role: existing.role,
            contentBlocks: blocks,
            images: existing.images,
            timestamp: existing.timestamp,
            isComplete: false
        )
    }

    public func appendStreamEventToCurrentMessage(_ event: AIStreamEvent) {
        guard let id = currentStreamingMessageId,
              let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let existing = messages[index]
        var blocks = existing.contentBlocks
        switch event {
        case .textDelta(let chunk):
            if case .text(let prev) = blocks.last {
                blocks[blocks.count - 1] = .text(prev + chunk)
            } else {
                blocks.append(.text(chunk))
            }
        case .thinking(let content):
            blocks.append(.thinking(content))
        case .toolUse(let name, let detail):
            blocks.append(.toolUse(name: name, detail: detail))
        case .toolResult(let name, let summary, let isError):
            blocks.append(.toolResult(name: name, summary: summary, isError: isError))
        case .metrics(let duration, let cost, let turns):
            blocks.append(.metrics(duration: duration, cost: cost, turns: turns))
        }
        messages[index] = ChatMessage(
            id: existing.id,
            role: existing.role,
            contentBlocks: blocks,
            images: existing.images,
            timestamp: existing.timestamp,
            isComplete: false
        )
    }

    public func finalizeCurrentStreamingMessage() {
        guard let id = currentStreamingMessageId,
              let index = messages.firstIndex(where: { $0.id == id }) else {
            currentStreamingMessageId = nil
            return
        }
        let existing = messages[index]
        messages[index] = ChatMessage(
            id: existing.id,
            role: existing.role,
            contentBlocks: existing.contentBlocks,
            images: existing.images,
            timestamp: existing.timestamp,
            isComplete: true
        )
        currentStreamingMessageId = nil
    }

    // MARK: - Session Management

    public func listSessions() async -> [ChatSession] {
        await provider.listSessions(workingDirectory: workingDirectory)
    }

    public nonisolated func loadSessionDetails(sessionId: String, summary: String, lastModified: Date, workingDirectory: String) -> SessionDetails? {
        provider.getSessionDetails(sessionId: sessionId, summary: summary, lastModified: lastModified, workingDirectory: workingDirectory)
    }

    public func resumeSession(_ sessionId: String) async {
        self.messages = []
        self.sessionId = sessionId
        self.hasStartedSession = true
        self.isLoadingHistory = true

        let sessionMessages = await provider.loadSessionMessages(sessionId: sessionId, workingDirectory: workingDirectory)
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

        if settings.resumeLastSession, provider.supportsSessionHistory {
            self.isLoadingHistory = true
            let sessions = await provider.listSessions(workingDirectory: resolvedPath)
            guard self.workingDirectory == resolvedPath else { return }
            if let mostRecent = sessions.first {
                let sessionMessages = await provider.loadSessionMessages(sessionId: mostRecent.id, workingDirectory: resolvedPath)
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
        let sysPrompt = await MainActor.run { systemPrompt }

        let assistantMessageId = UUID()
        let placeholderMessage = ChatMessage(
            id: assistantMessageId,
            role: .assistant,
            contentBlocks: [],
            timestamp: Date()
        )

        await MainActor.run {
            messages.append(placeholderMessage)
        }

        actor StreamAccumulator {
            var blocks: [AIContentBlock] = []

            func apply(_ event: AIStreamEvent) -> [AIContentBlock] {
                switch event {
                case .textDelta(let chunk):
                    if case .text(let existing) = blocks.last {
                        blocks[blocks.count - 1] = .text(existing + chunk)
                    } else {
                        blocks.append(.text(chunk))
                    }
                case .thinking(let content):
                    blocks.append(.thinking(content))
                case .toolUse(let name, let detail):
                    blocks.append(.toolUse(name: name, detail: detail))
                case .toolResult(let name, let summary, let isError):
                    blocks.append(.toolResult(name: name, summary: summary, isError: isError))
                case .metrics(let duration, let cost, let turns):
                    blocks.append(.metrics(duration: duration, cost: cost, turns: turns))
                }
                return blocks
            }
        }

        let accumulator = StreamAccumulator()

        let options = ChatProviderOptions(
            sessionId: resumeId,
            systemPrompt: sysPrompt,
            workingDirectory: workingDir
        )

        do {
            let result = try await provider.sendMessage(
                content,
                images: images,
                options: options
            ) { @Sendable event in
                Task {
                    let updatedBlocks = await accumulator.apply(event)
                    await MainActor.run { [updatedBlocks] in
                        if let index = self.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                            self.messages[index] = ChatMessage(
                                id: assistantMessageId,
                                role: .assistant,
                                contentBlocks: updatedBlocks,
                                timestamp: self.messages[index].timestamp
                            )
                        }
                    }
                }
            }

            await MainActor.run {
                hasStartedSession = true
                if let newSessionId = result.sessionId {
                    sessionId = newSessionId
                }

                if let index = messages.firstIndex(where: { $0.id == assistantMessageId }) {
                    let existing = messages[index]
                    messages[index] = ChatMessage(
                        id: existing.id,
                        role: existing.role,
                        contentBlocks: existing.contentBlocks,
                        images: existing.images,
                        timestamp: existing.timestamp,
                        isComplete: true
                    )
                }
                isProcessing = false
            }
        } catch {
            await MainActor.run {
                let displayName = providerDisplayName
                if let index = messages.firstIndex(where: { $0.id == assistantMessageId }) {
                    messages[index] = ChatMessage(
                        id: assistantMessageId,
                        role: .assistant,
                        content: "Error running \(displayName): \(error.localizedDescription)",
                        timestamp: messages[index].timestamp,
                        isComplete: true
                    )
                }
                isProcessing = false
            }
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
