import Foundation
@preconcurrency import SwiftAnthropic

public struct ChatResponse: Sendable {
    public let textContent: String
    public let toolResults: [String]

    public init(textContent: String, toolResults: [String] = []) {
        self.textContent = textContent
        self.toolResults = toolResults
    }
}

public enum ChatEvent: Sendable {
    case text(String)
    case toolUse(name: String, id: String)
    case toolResult(String)
    case completed(ChatResponse)
    case error(Error)
}

public typealias ToolExecutionHandler = @MainActor (MessageResponse.Content.ToolUse) async throws -> String
