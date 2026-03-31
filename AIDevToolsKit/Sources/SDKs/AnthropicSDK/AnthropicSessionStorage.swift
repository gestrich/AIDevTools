import AIOutputSDK
import Foundation

struct PersistedMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct PersistedSession: Codable, Sendable {
    let id: String
    let lastModified: Date
    let summary: String
    let messages: [PersistedMessage]
}

actor AnthropicSessionStorage {
    private let sessionsDirectory: URL

    init(baseDirectory: URL? = nil) {
        let base = baseDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aidevtools")
            .appendingPathComponent("anthropic")
            .appendingPathComponent("sessions")
        self.sessionsDirectory = base
    }

    func save(sessionId: String, messages: [(role: String, content: String)]) throws {
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let summary = messages.first(where: { $0.role == "user" })?.content
            .prefix(100)
            .description ?? "Conversation"

        let persisted = PersistedSession(
            id: sessionId,
            lastModified: Date(),
            summary: String(summary),
            messages: messages.map { PersistedMessage(role: $0.role, content: $0.content) }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(persisted)
        let fileURL = sessionsDirectory.appendingPathComponent("\(sessionId).json")
        try data.write(to: fileURL, options: .atomic)
    }

    func listSessions() -> [ChatSession] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> ChatSession? in
                guard let data = try? Data(contentsOf: url),
                      let session = try? decoder.decode(PersistedSession.self, from: data) else {
                    return nil
                }
                return ChatSession(
                    id: session.id,
                    lastModified: session.lastModified,
                    summary: session.summary
                )
            }
            .sorted { $0.lastModified > $1.lastModified }
    }

    func loadMessages(sessionId: String) -> [ChatSessionMessage] {
        let fileURL = sessionsDirectory.appendingPathComponent("\(sessionId).json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: fileURL),
              let session = try? decoder.decode(PersistedSession.self, from: data) else {
            return []
        }

        return session.messages.map { msg in
            ChatSessionMessage(
                content: msg.content,
                role: msg.role == "user" ? .user : .assistant
            )
        }
    }

    func loadPersistedMessages(sessionId: String) -> [PersistedMessage] {
        let fileURL = sessionsDirectory.appendingPathComponent("\(sessionId).json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: fileURL),
              let session = try? decoder.decode(PersistedSession.self, from: data) else {
            return []
        }

        return session.messages
    }
}
