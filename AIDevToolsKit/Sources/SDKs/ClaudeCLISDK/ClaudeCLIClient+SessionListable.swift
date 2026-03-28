import AIOutputSDK
import Foundation

extension ClaudeCLIClient: SessionListable {

    public func listSessions(workingDirectory: String) async -> [ChatSession] {
        await Task.detached {
            Self.listSessionsSync(workingDirectory: workingDirectory)
        }.value
    }

    public func loadSessionMessages(sessionId: String, workingDirectory: String) async -> [ChatSessionMessage] {
        await Task.detached {
            Self.loadSessionMessagesSync(sessionId: sessionId, workingDirectory: workingDirectory)
        }.value
    }

    // MARK: - Session Details (Claude-specific)

    public func getSessionDetails(sessionId: String, summary: String, lastModified: Date, workingDirectory: String) -> ClaudeSessionDetails? {
        let filePath = Self.sessionFilePath(sessionId: sessionId, workingDirectory: workingDirectory)

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

        let session = ChatSession(id: sessionId, lastModified: lastModified, summary: summary)
        return ClaudeSessionDetails(cwd: cwd, gitBranch: gitBranch, rawJsonLines: rawJsonLines, session: session)
    }

    // MARK: - Private Helpers

    private static func listSessionsSync(workingDirectory: String) -> [ChatSession] {
        let projectPath = sessionDirectoryPath(workingDirectory: workingDirectory)
        guard FileManager.default.fileExists(atPath: projectPath) else { return [] }

        var sessions: [ChatSession] = []

        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: projectPath)
            for file in files where file.hasSuffix(".jsonl") {
                let sessionId = (file as NSString).deletingPathExtension
                let filePath = (projectPath as NSString).appendingPathComponent(file)

                if let summary = findSummaryInSessionFile(at: filePath) {
                    let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
                    let modificationDate = attributes[.modificationDate] as? Date ?? Date()
                    sessions.append(ChatSession(id: sessionId, lastModified: modificationDate, summary: summary))
                }
            }
        } catch {
            // Directory listing failed
        }

        return sessions.sorted { $0.lastModified > $1.lastModified }
    }

    private static func loadSessionMessagesSync(sessionId: String, workingDirectory: String) -> [ChatSessionMessage] {
        let filePath = sessionFilePath(sessionId: sessionId, workingDirectory: workingDirectory)
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return [] }

        var messages: [ChatSessionMessage] = []

        for line in content.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String,
                  type == "user" || type == "assistant",
                  let message = json["message"] as? [String: Any] else { continue }

            let text = extractTextContent(from: message)
            guard !text.isEmpty else { continue }

            let role: ChatSessionMessage.ChatSessionMessageRole = type == "user" ? .user : .assistant
            messages.append(ChatSessionMessage(content: text, role: role))
        }

        return messages
    }

    private static func findSummaryInSessionFile(at filePath: String) -> String? {
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

    private static func extractTextContent(from message: [String: Any]) -> String {
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

    private static func sessionDirectoryPath(workingDirectory: String) -> String {
        let projectsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects")
        let projectDirName = projectDirName(from: workingDirectory)
        return (projectsDir as NSString).appendingPathComponent(projectDirName)
    }

    private static func sessionFilePath(sessionId: String, workingDirectory: String) -> String {
        sessionDirectoryPath(workingDirectory: workingDirectory) + "/\(sessionId).jsonl"
    }

    private static func projectDirName(from workingDir: String) -> String {
        workingDir
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "_", with: "-")
    }
}

public struct ClaudeSessionDetails: Sendable {
    public let cwd: String?
    public let gitBranch: String?
    public let rawJsonLines: [String]
    public let session: ChatSession

    public init(cwd: String?, gitBranch: String?, rawJsonLines: [String], session: ChatSession) {
        self.cwd = cwd
        self.gitBranch = gitBranch
        self.rawJsonLines = rawJsonLines
        self.session = session
    }
}
