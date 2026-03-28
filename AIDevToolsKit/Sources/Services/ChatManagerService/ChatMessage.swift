import AIOutputSDK
import Foundation

public struct ChatMessage: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let role: Role
    public let content: String
    public let images: [ImageAttachment]
    public let timestamp: Date
    public let isComplete: Bool

    public enum Role: Sendable, Equatable {
        case assistant
        case user
    }

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        images: [ImageAttachment] = [],
        timestamp: Date = Date(),
        isComplete: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.images = images
        self.timestamp = timestamp
        self.isComplete = isComplete
    }

    public var contentLines: [ContentLine] {
        var lines: [ContentLine] = []
        var currentIndex = 0

        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("🧠 ") {
                lines.append(ContentLine(id: currentIndex, type: .thinking, text: line))
            } else if line.hasPrefix("🔧 ") {
                lines.append(ContentLine(id: currentIndex, type: .tool, text: line))
            } else if !line.isEmpty {
                lines.append(ContentLine(id: currentIndex, type: .text, text: line))
            }
            currentIndex += 1
        }

        return lines
    }

    public var shouldCollapseThinking: Bool {
        guard role == .assistant, isComplete else { return false }

        let lines = contentLines
        let hasThinking = lines.contains { $0.type == .thinking || $0.type == .tool }
        let hasText = lines.contains { $0.type == .text }

        return hasThinking && hasText
    }
}

public struct ContentLine: Identifiable, Sendable, Equatable {
    public let id: Int
    public let type: ContentType
    public let text: String

    public enum ContentType: Sendable, Equatable {
        case text
        case thinking
        case tool
    }
}

