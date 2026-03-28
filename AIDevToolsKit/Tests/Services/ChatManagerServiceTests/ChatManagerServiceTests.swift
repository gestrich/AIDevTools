import Foundation
import Testing
@testable import ChatManagerService

struct ChatMessageTests {

    // MARK: - ContentLines Parsing

    @Test func contentLinesClassifiesThinkingLines() {
        let message = ChatMessage(role: .assistant, content: "🧠 Thinking about this...")
        let lines = message.contentLines
        #expect(lines.count == 1)
        #expect(lines[0].type == .thinking)
    }

    @Test func contentLinesClassifiesToolLines() {
        let message = ChatMessage(role: .assistant, content: "🔧 Running grep command")
        let lines = message.contentLines
        #expect(lines.count == 1)
        #expect(lines[0].type == .tool)
    }

    @Test func contentLinesClassifiesTextLines() {
        let message = ChatMessage(role: .assistant, content: "Here is the answer.")
        let lines = message.contentLines
        #expect(lines.count == 1)
        #expect(lines[0].type == .text)
    }

    @Test func contentLinesHandlesMixedContent() {
        let content = """
        🧠 Let me think...
        🔧 Reading file.swift
        Here is the result.
        """
        let message = ChatMessage(role: .assistant, content: content)
        let lines = message.contentLines
        #expect(lines.count == 3)
        #expect(lines[0].type == .thinking)
        #expect(lines[1].type == .tool)
        #expect(lines[2].type == .text)
    }

    @Test func contentLinesSkipsEmptyLines() {
        let message = ChatMessage(role: .assistant, content: "Hello\n\nWorld")
        let lines = message.contentLines
        #expect(lines.count == 2)
        #expect(lines[0].text == "Hello")
        #expect(lines[1].text == "World")
    }

    // MARK: - shouldCollapseThinking

    @Test func shouldCollapseThinkingReturnsTrueForCompletedMessageWithBothTypes() {
        let content = "🧠 Thinking\nHere is the answer."
        let message = ChatMessage(role: .assistant, content: content, isComplete: true)
        #expect(message.shouldCollapseThinking == true)
    }

    @Test func shouldCollapseThinkingReturnsFalseForIncompleteMessage() {
        let content = "🧠 Thinking\nHere is the answer."
        let message = ChatMessage(role: .assistant, content: content, isComplete: false)
        #expect(message.shouldCollapseThinking == false)
    }

    @Test func shouldCollapseThinkingReturnsFalseForUserMessage() {
        let message = ChatMessage(role: .user, content: "🧠 Not thinking", isComplete: true)
        #expect(message.shouldCollapseThinking == false)
    }

    @Test func shouldCollapseThinkingReturnsFalseWhenOnlyThinking() {
        let message = ChatMessage(role: .assistant, content: "🧠 Just thinking", isComplete: true)
        #expect(message.shouldCollapseThinking == false)
    }
}

struct ChatSettingsTests {

    @Test func defaultValues() {
        let settings = ChatSettings()
        #expect(type(of: settings.enableStreaming) == Bool.self)
        #expect(type(of: settings.resumeLastSession) == Bool.self)
        #expect(type(of: settings.verboseMode) == Bool.self)
        #expect(settings.maxThinkingTokens >= 1024)
    }
}
