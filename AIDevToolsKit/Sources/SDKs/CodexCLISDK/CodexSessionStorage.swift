import AIOutputSDK
import Foundation

struct CodexSessionStorage: Sendable {
    private let codexHome: URL

    init(codexHome: URL? = nil) {
        self.codexHome = codexHome ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
    }

    // MARK: - Session Listing

    func listSessions() -> [ChatSession] {
        let indexPath = codexHome.appendingPathComponent("session_index.jsonl")
        guard let data = try? Data(contentsOf: indexPath),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }

        // session_index.jsonl is append-only, newest-wins for duplicate IDs
        var sessionsByID: [String: ChatSession] = [:]
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(SessionIndexEntry.self, from: lineData) else {
                continue
            }

            let date = dateFormatter.date(from: entry.updatedAt) ?? Date.distantPast
            sessionsByID[entry.id] = ChatSession(
                id: entry.id,
                lastModified: date,
                summary: entry.threadName
            )
        }

        return sessionsByID.values.sorted { $0.lastModified > $1.lastModified }
    }

    // MARK: - Message Loading

    func loadMessages(sessionId: String) -> [ChatSessionMessage] {
        guard let filePath = findRolloutFile(sessionId: sessionId) else {
            return []
        }

        let ext = filePath.pathExtension
        if ext == "jsonl" {
            return parseJSONLRollout(at: filePath)
        } else if ext == "json" {
            return parseLegacyJSON(at: filePath)
        }
        return []
    }

    // MARK: - Rollout File Discovery

    private func findRolloutFile(sessionId: String) -> URL? {
        let sessionsDir = codexHome.appendingPathComponent("sessions")
        return findFileRecursively(in: sessionsDir, containing: sessionId)
    }

    private func findFileRecursively(in directory: URL, containing sessionId: String) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            let filename = fileURL.lastPathComponent
            if filename.contains(sessionId) && (filename.hasSuffix(".jsonl") || filename.hasSuffix(".json")) {
                return fileURL
            }
        }
        return nil
    }

    // MARK: - JSONL Rollout Parsing (Current Codex format)

    private func parseJSONLRollout(at url: URL) -> [ChatSessionMessage] {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }

        var messages: [ChatSessionMessage] = []

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let rolloutLine = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            guard rolloutLine["type"] as? String == "response_item",
                  let payload = rolloutLine["payload"] as? [String: Any],
                  payload["type"] as? String == "message",
                  let role = payload["role"] as? String,
                  role == "user" || role == "assistant" else {
                continue
            }

            let text = extractText(from: payload["content"])
            guard !text.isEmpty else { continue }

            messages.append(ChatSessionMessage(
                content: text,
                role: role == "user" ? .user : .assistant
            ))
        }

        return messages
    }

    // MARK: - Legacy JSON Parsing (Old Codex format)

    private func parseLegacyJSON(at url: URL) -> [ChatSessionMessage] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }

        var messages: [ChatSessionMessage] = []

        for item in items {
            guard item["type"] as? String == "message",
                  let role = item["role"] as? String,
                  role == "user" || role == "assistant" else {
                continue
            }

            let text = extractText(from: item["content"])
            guard !text.isEmpty else { continue }

            messages.append(ChatSessionMessage(
                content: text,
                role: role == "user" ? .user : .assistant
            ))
        }

        return messages
    }

    // MARK: - Content Extraction

    private func extractText(from content: Any?) -> String {
        if let text = content as? String {
            return text
        }

        if let contentArray = content as? [[String: Any]] {
            return contentArray.compactMap { obj -> String? in
                guard let type = obj["type"] as? String,
                      type == "input_text" || type == "output_text" || type == "text" else {
                    return nil
                }
                return obj["text"] as? String
            }.joined(separator: "\n")
        }

        return ""
    }
}

// MARK: - Codable Models

private struct SessionIndexEntry: Decodable {
    let id: String
    let threadName: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
        case updatedAt = "updated_at"
    }
}
