import ClaudeCLISDK
import Foundation
import Observation

@Observable
@MainActor
public final class ClaudeCodeChatManager {
    public private(set) var sessionState: SessionState
    public private(set) var isProcessing: Bool = false
    public private(set) var isLoadingHistory: Bool = false
    public let settings: ClaudeCodeChatSettings
    public private(set) var messageQueue: [QueuedMessage] = []

    private let claudeClient: ClaudeCLIClient
    private var currentTask: Task<Void, Never>?

    public var messages: [ClaudeCodeChatMessage] { sessionState.messages }
    public var workingDirectory: String { sessionState.workingDirectory }
    public var currentSessionId: String? { sessionState.sessionId }

    public init(
        workingDirectory: String? = nil,
        settings: ClaudeCodeChatSettings = ClaudeCodeChatSettings(),
        claudeClient: ClaudeCLIClient = ClaudeCLIClient()
    ) {
        self.claudeClient = claudeClient
        self.settings = settings

        let rawWorkingDir = workingDirectory ?? FileManager.default.currentDirectoryPath
        let resolvedWorkingDir = Self.resolveSymlinks(in: rawWorkingDir)
        self.sessionState = SessionState(workingDirectory: resolvedWorkingDir)

        if settings.resumeLastSession {
            self.isLoadingHistory = true
            let workDir = resolvedWorkingDir
            Task {
                let sessions = await Self.listSessionsFromDisk(workingDirectory: workDir)
                if let mostRecent = sessions.first {
                    let messages = await Self.loadSessionMessages(sessionId: mostRecent.id, workingDirectory: workDir)
                    self.sessionState = SessionState(
                        workingDirectory: workDir,
                        messages: messages,
                        sessionId: mostRecent.id,
                        hasStartedSession: true
                    )
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

    public func clearMessages() {
        sessionState.messages.removeAll()
    }

    public func setWorkingDirectory(_ path: String) async {
        let resolvedPath = Self.resolveSymlinks(in: path)
        guard resolvedPath != sessionState.workingDirectory else { return }

        self.sessionState = SessionState(workingDirectory: resolvedPath)

        if settings.resumeLastSession {
            self.isLoadingHistory = true
            let sessions = await Self.listSessionsFromDisk(workingDirectory: resolvedPath)
            guard self.sessionState.workingDirectory == resolvedPath else { return }
            if let mostRecent = sessions.first {
                let messages = await Self.loadSessionMessages(sessionId: mostRecent.id, workingDirectory: resolvedPath)
                guard self.sessionState.workingDirectory == resolvedPath else { return }
                self.sessionState = SessionState(
                    workingDirectory: resolvedPath,
                    messages: messages,
                    sessionId: mostRecent.id,
                    hasStartedSession: true
                )
            }
            self.isLoadingHistory = false
        }
    }

    public func removeQueuedMessage(id: UUID) {
        messageQueue.removeAll { $0.id == id }
    }

    public func clearQueue() {
        messageQueue.removeAll()
    }

    public func startNewConversation() {
        self.sessionState = SessionState(workingDirectory: sessionState.workingDirectory)
        messageQueue.removeAll()
    }

    public func resumeSession(_ sessionId: String) async {
        let workDir = sessionState.workingDirectory
        self.sessionState = SessionState(
            workingDirectory: workDir,
            messages: [],
            sessionId: sessionId,
            hasStartedSession: true
        )
        self.isLoadingHistory = true
        let messages = await Self.loadSessionMessages(sessionId: sessionId, workingDirectory: workDir)
        self.sessionState.messages = messages
        self.isLoadingHistory = false
    }

    public func cancelCurrentRequest() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
    }

    public func listSessions() async -> [ClaudeSession] {
        await Self.listSessionsFromDisk(workingDirectory: workingDirectory)
    }

    public nonisolated static func listSessionsFromDisk(workingDirectory: String) async -> [ClaudeSession] {
        await Task.detached {
            listSessionsSync(workingDirectory: workingDirectory)
        }.value
    }

    private nonisolated static func listSessionsSync(workingDirectory: String) -> [ClaudeSession] {
        let projectsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects")
        let projectDirName = projectDirName(from: workingDirectory)
        let projectPath = (projectsDir as NSString).appendingPathComponent(projectDirName)

        guard FileManager.default.fileExists(atPath: projectPath) else { return [] }

        var sessions: [ClaudeSession] = []

        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: projectPath)
            for file in files where file.hasSuffix(".jsonl") {
                let sessionId = (file as NSString).deletingPathExtension
                let filePath = (projectPath as NSString).appendingPathComponent(file)

                if let summary = findSummaryInSessionFile(at: filePath) {
                    let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
                    let modificationDate = attributes[.modificationDate] as? Date ?? Date()
                    sessions.append(ClaudeSession(id: sessionId, summary: summary, lastModified: modificationDate))
                }
            }
        } catch {
            // Directory listing failed
        }

        return sessions.sorted { $0.lastModified > $1.lastModified }
    }

    // MARK: - Internal

    private nonisolated func sendMessageInternal(_ content: String, images: [ImageAttachment] = []) async {
        let userMessage = ClaudeCodeChatMessage(role: .user, content: content, images: images)
        await MainActor.run {
            sessionState.messages.append(userMessage)
            isProcessing = true
        }

        let shouldContinue = await MainActor.run {
            settings.resumeLastSession && sessionState.hasStartedSession
        }
        let resumeId = await MainActor.run { sessionState.sessionId }
        let serviceSettings = await MainActor.run {
            (
                workingDir: workingDirectory,
                verbose: settings.verboseMode
            )
        }

        var promptText = content
        var imagePaths: [String] = []

        if !images.isEmpty {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-images-\(UUID().uuidString)")
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
        let placeholderMessage = ClaudeCodeChatMessage(
            id: assistantMessageId,
            role: .assistant,
            content: "",
            timestamp: Date()
        )

        await MainActor.run {
            sessionState.messages.append(placeholderMessage)
        }

        actor StreamAccumulator {
            var content = ""

            func append(_ chunk: String) -> String {
                content += chunk
                return content
            }
        }

        let accumulator = StreamAccumulator()

        var command = Claude(prompt: promptText)
        command.dangerouslySkipPermissions = true
        command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
        command.verbose = true
        if shouldContinue {
            if let resumeId {
                command.resume = resumeId
            } else {
                command.continueConversation = true
            }
        }

        do {
            let result = try await claudeClient.run(
                command: command,
                workingDirectory: serviceSettings.workingDir,
                onFormattedOutput: { @Sendable chunk in
                    Task {
                        let updatedContent = await accumulator.append(chunk)
                        await MainActor.run { [updatedContent] in
                            if let index = self.sessionState.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                                self.sessionState.messages[index] = ClaudeCodeChatMessage(
                                    id: assistantMessageId,
                                    role: .assistant,
                                    content: updatedContent,
                                    timestamp: self.sessionState.messages[index].timestamp
                                )
                            }
                        }
                    }
                }
            )

            let sessionId = parseSessionId(from: result.stdout)

            await MainActor.run {
                if result.exitCode == 0 {
                    sessionState.hasStartedSession = true
                    if let sessionId {
                        sessionState.sessionId = sessionId
                    }
                }

                if let index = sessionState.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                    let existing = sessionState.messages[index]

                    if result.exitCode != 0 {
                        let errorMessage: String
                        if result.exitCode == 130 || result.exitCode == 143 {
                            errorMessage = "Request interrupted by user"
                        } else {
                            errorMessage = "Error running Claude (exit code \(result.exitCode))\n\(result.stderr)"
                        }
                        sessionState.messages[index] = ClaudeCodeChatMessage(
                            id: assistantMessageId,
                            role: .assistant,
                            content: errorMessage,
                            timestamp: existing.timestamp,
                            isComplete: true
                        )
                    } else {
                        sessionState.messages[index] = ClaudeCodeChatMessage(
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
                if let index = sessionState.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                    sessionState.messages[index] = ClaudeCodeChatMessage(
                        id: assistantMessageId,
                        role: .assistant,
                        content: "Error: \(error.localizedDescription)",
                        timestamp: sessionState.messages[index].timestamp,
                        isComplete: true
                    )
                }
                isProcessing = false
            }
        }

        // Cleanup temp image files
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

    // MARK: - Session File Parsing

    private nonisolated func parseSessionId(from stdout: String) -> String? {
        let decoder = JSONDecoder()
        for line in stdout.components(separatedBy: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            if let result = try? decoder.decode(ClaudeResultEvent.self, from: data),
               result.type == "result",
               let sessionId = result.sessionId {
                return sessionId
            }
        }
        return nil
    }

    private nonisolated static func findSummaryInSessionFile(at filePath: String) -> String? {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: "\n")
        for line in lines {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String,
                  type == "summary",
                  let summary = json["summary"] as? String else { continue }
            return summary
        }

        for line in lines {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String,
                  type == "user",
                  let message = json["message"] as? [String: Any],
                  let content = message["content"] as? String else { continue }
            return String(content.prefix(50)) + (content.count > 50 ? "..." : "")
        }

        return nil
    }

    // MARK: - Session History Loading

    private nonisolated static func loadSessionMessages(sessionId: String, workingDirectory: String) async -> [ClaudeCodeChatMessage] {
        await Task.detached {
            loadSessionMessagesSync(sessionId: sessionId, workingDirectory: workingDirectory)
        }.value
    }

    private nonisolated static func loadSessionMessagesSync(sessionId: String, workingDirectory: String) -> [ClaudeCodeChatMessage] {
        let projectsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects")
        let projectDirName = projectDirName(from: workingDirectory)
        let filePath = (projectsDir as NSString)
            .appendingPathComponent(projectDirName)
            .appending("/\(sessionId).jsonl")

        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return [] }

        var messages: [ClaudeCodeChatMessage] = []

        for line in content.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String,
                  type == "user" || type == "assistant",
                  let message = json["message"] as? [String: Any] else { continue }

            let text = extractTextContent(from: message)
            guard !text.isEmpty else { continue }

            let role: ClaudeCodeChatMessage.Role = type == "user" ? .user : .assistant
            messages.append(ClaudeCodeChatMessage(
                role: role,
                content: text,
                isComplete: true
            ))
        }

        return messages
    }

    private nonisolated static func extractTextContent(from message: [String: Any]) -> String {
        if let contentArray = message["content"] as? [[String: Any]] {
            let texts = contentArray.compactMap { block -> String? in
                guard let blockType = block["type"] as? String, blockType == "text",
                      let text = block["text"] as? String else { return nil }
                return text
            }
            return texts.joined(separator: "\n")
        }

        if let contentString = message["content"] as? String {
            return contentString
        }

        return ""
    }

    // MARK: - Session Details

    public nonisolated static func getSessionDetails(for session: ClaudeSession, workingDirectory: String) -> SessionDetails? {
        let projectsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects")
        let projectDirName = projectDirName(from: workingDirectory)
        let filePath = (projectsDir as NSString)
            .appendingPathComponent(projectDirName)
            .appending("/\(session.id).jsonl")

        guard FileManager.default.fileExists(atPath: filePath),
              let fileContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return nil
        }

        var cwd: String?
        var gitBranch: String?
        var rawJsonLines: [String] = []

        for line in fileContents.components(separatedBy: "\n") where !line.isEmpty {
            rawJsonLines.append(line)

            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if cwd == nil { cwd = json["cwd"] as? String }
            if gitBranch == nil { gitBranch = json["gitBranch"] as? String }
        }

        return SessionDetails(session: session, cwd: cwd, gitBranch: gitBranch, rawJsonLines: rawJsonLines)
    }

    // MARK: - Helpers

    private nonisolated static func projectDirName(from workingDir: String) -> String {
        workingDir
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "_", with: "-")
    }

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
