import AIOutputSDK
import Testing
@testable import ClaudeCLISDK

@Suite("ClaudeStreamFormatter.formatStructured")
struct ClaudeStreamFormatterTests {

    let formatter = ClaudeStreamFormatter()

    // MARK: - Fixtures

    static let textBlock = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Hello world"}]}}"#

    static let thinkingBlock = #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"Let me analyze this."}]}}"#

    static let bashToolUse = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls -la"}}]}}"#

    static let readToolUse = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/tmp/file.txt"}}]}}"#

    static let structuredOutputToolUse = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"StructuredOutput","input":{"result":"ok"}}]}}"#

    static let toolResult = #"{"type":"user","message":{"content":[{"type":"tool_result","content":"file.txt\ndir/","tool_use_id":"toolu_001"}]}}"#

    static let toolResultError = #"{"type":"user","message":{"content":[{"type":"tool_result","content":"Permission denied","tool_use_id":"toolu_002","is_error":true}]}}"#

    static let resultEvent = #"{"type":"result","subtype":"success","is_error":false,"duration_ms":5000,"num_turns":2,"total_cost_usd":0.05}"#

    static let multipleBlocks = #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"Let me think."},{"type":"text","text":"Done."}]}}"#

    // MARK: - Text block

    @Test func textBlockEmitsTextDelta() {
        // Arrange — formatter is the struct-level instance

        // Act
        let events = formatter.formatStructured(Self.textBlock)

        // Assert
        #expect(events.count == 1)
        if case .textDelta(let text) = events[0] {
            #expect(text == "Hello world")
        } else {
            Issue.record("Expected .textDelta, got \(events[0])")
        }
    }

    // MARK: - Thinking block

    @Test func thinkingBlockEmitsThinking() {
        // Arrange — formatter is the struct-level instance

        // Act
        let events = formatter.formatStructured(Self.thinkingBlock)

        // Assert
        #expect(events.count == 1)
        if case .thinking(let content) = events[0] {
            #expect(content == "Let me analyze this.")
        } else {
            Issue.record("Expected .thinking, got \(events[0])")
        }
    }

    // MARK: - Tool use

    @Test func bashToolUseEmitsToolUseWithCommand() {
        // Arrange — formatter is the struct-level instance

        // Act
        let events = formatter.formatStructured(Self.bashToolUse)

        // Assert
        #expect(events.count == 1)
        if case .toolUse(let name, let detail) = events[0] {
            #expect(name == "Bash")
            #expect(detail == "ls -la")
        } else {
            Issue.record("Expected .toolUse, got \(events[0])")
        }
    }

    @Test func readToolUseEmitsToolUseWithFilePath() {
        // Arrange — formatter is the struct-level instance

        // Act
        let events = formatter.formatStructured(Self.readToolUse)

        // Assert
        #expect(events.count == 1)
        if case .toolUse(let name, let detail) = events[0] {
            #expect(name == "Read")
            #expect(detail == "/tmp/file.txt")
        } else {
            Issue.record("Expected .toolUse, got \(events[0])")
        }
    }

    @Test func structuredOutputToolUseIsFiltered() {
        // Arrange — formatter is the struct-level instance

        // Act
        let events = formatter.formatStructured(Self.structuredOutputToolUse)

        // Assert
        #expect(events.isEmpty)
    }

    // MARK: - Tool result

    @Test func toolResultEmitsToolResult() {
        // Arrange — formatter is the struct-level instance

        // Act
        let events = formatter.formatStructured(Self.toolResult)

        // Assert
        #expect(events.count == 1)
        if case .toolResult(_, let summary, let isError) = events[0] {
            #expect(summary.contains("file.txt"))
            #expect(isError == false)
        } else {
            Issue.record("Expected .toolResult, got \(events[0])")
        }
    }

    @Test func toolResultErrorFlagIsPreserved() {
        // Arrange — formatter is the struct-level instance

        // Act
        let events = formatter.formatStructured(Self.toolResultError)

        // Assert
        #expect(events.count == 1)
        if case .toolResult(_, _, let isError) = events[0] {
            #expect(isError == true)
        } else {
            Issue.record("Expected .toolResult, got \(events[0])")
        }
    }

    // MARK: - Metrics

    @Test func resultEventEmitsMetrics() {
        // Arrange — formatter is the struct-level instance

        // Act
        let events = formatter.formatStructured(Self.resultEvent)

        // Assert
        #expect(events.count == 1)
        if case .metrics(let duration, let cost, let turns) = events[0] {
            #expect(duration == 5.0)
            #expect(cost == 0.05)
            #expect(turns == 2)
        } else {
            Issue.record("Expected .metrics, got \(events[0])")
        }
    }

    // MARK: - Multiple blocks in one event

    @Test func multipleBlocksProduceMultipleEvents() {
        // Arrange — formatter is the struct-level instance

        // Act
        let events = formatter.formatStructured(Self.multipleBlocks)

        // Assert
        #expect(events.count == 2)
        if case .thinking(let content) = events[0] {
            #expect(content == "Let me think.")
        } else {
            Issue.record("Expected .thinking at index 0, got \(events[0])")
        }
        if case .textDelta(let text) = events[1] {
            #expect(text == "Done.")
        } else {
            Issue.record("Expected .textDelta at index 1, got \(events[1])")
        }
    }

    // MARK: - Multi-line chunks

    @Test func multiLineChunkParsesAllEvents() {
        // Arrange
        let chunk = Self.textBlock + "\n" + Self.resultEvent

        // Act
        let events = formatter.formatStructured(chunk)

        // Assert
        #expect(events.count == 2)
    }

    // MARK: - Edge cases

    @Test func emptyInputReturnsNoEvents() {
        // Arrange — formatter is the struct-level instance

        // Act
        let events = formatter.formatStructured("")

        // Assert
        #expect(events.isEmpty)
    }

    @Test func unknownEventTypeReturnsNoEvents() {
        // Arrange
        let unknown = #"{"type":"system","subtype":"init","session_id":"abc123"}"#

        // Act
        let events = formatter.formatStructured(unknown)

        // Assert
        #expect(events.isEmpty)
    }
}
