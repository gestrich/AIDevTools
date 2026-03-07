import Foundation
import Testing
@testable import ClaudeCodeChatService

struct ClaudeCodeChatMessageTests {

    // MARK: - ContentLines Parsing

    @Test func contentLinesClassifiesThinkingLines() {
        // Arrange
        let message = ClaudeCodeChatMessage(role: .assistant, content: "🧠 Thinking about this...")

        // Act
        let lines = message.contentLines

        // Assert
        #expect(lines.count == 1)
        #expect(lines[0].type == .thinking)
    }

    @Test func contentLinesClassifiesToolLines() {
        // Arrange
        let message = ClaudeCodeChatMessage(role: .assistant, content: "🔧 Running grep command")

        // Act
        let lines = message.contentLines

        // Assert
        #expect(lines.count == 1)
        #expect(lines[0].type == .tool)
    }

    @Test func contentLinesClassifiesTextLines() {
        // Arrange
        let message = ClaudeCodeChatMessage(role: .assistant, content: "Here is the answer.")

        // Act
        let lines = message.contentLines

        // Assert
        #expect(lines.count == 1)
        #expect(lines[0].type == .text)
    }

    @Test func contentLinesHandlesMixedContent() {
        // Arrange
        let content = """
        🧠 Let me think...
        🔧 Reading file.swift
        Here is the result.
        """
        let message = ClaudeCodeChatMessage(role: .assistant, content: content)

        // Act
        let lines = message.contentLines

        // Assert
        #expect(lines.count == 3)
        #expect(lines[0].type == .thinking)
        #expect(lines[1].type == .tool)
        #expect(lines[2].type == .text)
    }

    @Test func contentLinesSkipsEmptyLines() {
        // Arrange
        let message = ClaudeCodeChatMessage(role: .assistant, content: "Hello\n\nWorld")

        // Act
        let lines = message.contentLines

        // Assert
        #expect(lines.count == 2)
        #expect(lines[0].text == "Hello")
        #expect(lines[1].text == "World")
    }

    // MARK: - shouldCollapseThinking

    @Test func shouldCollapseThinkingReturnsTrueForCompletedMessageWithBothTypes() {
        // Arrange
        let content = "🧠 Thinking\nHere is the answer."
        let message = ClaudeCodeChatMessage(role: .assistant, content: content, isComplete: true)

        // Act & Assert
        #expect(message.shouldCollapseThinking == true)
    }

    @Test func shouldCollapseThinkingReturnsFalseForIncompleteMessage() {
        // Arrange
        let content = "🧠 Thinking\nHere is the answer."
        let message = ClaudeCodeChatMessage(role: .assistant, content: content, isComplete: false)

        // Act & Assert
        #expect(message.shouldCollapseThinking == false)
    }

    @Test func shouldCollapseThinkingReturnsFalseForUserMessage() {
        // Arrange
        let message = ClaudeCodeChatMessage(role: .user, content: "🧠 Not thinking", isComplete: true)

        // Act & Assert
        #expect(message.shouldCollapseThinking == false)
    }

    @Test func shouldCollapseThinkingReturnsFalseWhenOnlyThinking() {
        // Arrange
        let message = ClaudeCodeChatMessage(role: .assistant, content: "🧠 Just thinking", isComplete: true)

        // Act & Assert
        #expect(message.shouldCollapseThinking == false)
    }
}

struct SessionStateTests {

    @Test func initSetsDefaults() {
        // Arrange & Act
        let state = SessionState(workingDirectory: "/tmp/test")

        // Assert
        #expect(state.workingDirectory == "/tmp/test")
        #expect(state.messages.isEmpty)
        #expect(state.sessionId == nil)
        #expect(state.hasStartedSession == false)
    }

    @Test func initWithSessionId() {
        // Arrange & Act
        let state = SessionState(
            workingDirectory: "/tmp/test",
            messages: [],
            sessionId: "abc-123",
            hasStartedSession: true
        )

        // Assert
        #expect(state.sessionId == "abc-123")
        #expect(state.hasStartedSession == true)
    }
}

struct ClaudeCodeChatSettingsTests {

    @Test func defaultValues() {
        // Arrange & Act
        let settings = ClaudeCodeChatSettings()

        // Assert — defaults from UserDefaults or fallback
        #expect(type(of: settings.enableStreaming) == Bool.self)
        #expect(type(of: settings.resumeLastSession) == Bool.self)
        #expect(type(of: settings.verboseMode) == Bool.self)
        #expect(settings.maxThinkingTokens >= 1024)
    }
}
