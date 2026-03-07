import Testing
@testable import EvalSDK
@testable import EvalService

@Suite("CodexOutputParser")
struct CodexOutputParserTests {

    let parser = CodexOutputParser()

    // MARK: - Fixtures

    static let structuredSuccess = """
    {"type":"thread.started","thread_id":"019cb8e9-0000-0000-0000-000000000001"}
    {"type":"turn.started"}
    {"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"{\\"result\\":\\"PROBE_STRUCTURED_OK\\"}"}}
    {"type":"turn.completed","usage":{"input_tokens":15391,"cached_input_tokens":2560,"output_tokens":42}}
    """

    static let toolUsing = """
    {"type":"thread.started","thread_id":"019cb8e9-0000-0000-0000-000000000002"}
    {"type":"turn.started"}
    {"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"{\\"result\\":\\"Running a directory listing now.\\"}"}}
    {"type":"item.started","item":{"id":"item_1","type":"command_execution","command":"/bin/zsh -lc 'ls -1 | head -n 3'","aggregated_output":"","exit_code":null,"status":"in_progress"}}
    {"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"/bin/zsh -lc 'ls -1 | head -n 3'","aggregated_output":"AGENTS.md\\nAmazonWebServices\\nAviationMathUtils\\n","exit_code":0,"status":"completed"}}
    {"type":"item.completed","item":{"id":"item_2","type":"agent_message","text":"{\\"result\\":\\"First 3 entries: AGENTS.md, AmazonWebServices, AviationMathUtils.\\"}"}}
    {"type":"turn.completed","usage":{"input_tokens":31028,"cached_input_tokens":18048,"output_tokens":221}}
    """

    static let errorSchema = """
    {"type":"thread.started","thread_id":"019cb8e9-0000-0000-0000-000000000003"}
    {"type":"turn.started"}
    {"type":"error","message":"Invalid schema for response_format: enum value ALPHA does not validate against pattern ^BETA$"}
    {"type":"turn.failed","error":{"message":"Invalid schema for response_format: enum value ALPHA does not validate against pattern ^BETA$"}}
    """

    // MARK: - parse()

    @Test func parseStructuredSuccess() {
        let output = parser.parse(Self.structuredSuccess)
        #expect(output.rawEvents.count >= 3)
        let types = output.rawEvents.compactMap { $0["type"]?.stringValue }
        #expect(types.contains("thread.started"))
        #expect(types.contains("turn.completed"))
        #expect(types.contains("item.completed"))
    }

    @Test func parseToolUsing() {
        let output = parser.parse(Self.toolUsing)
        #expect(output.toolEvents.count == 1)
        let te = output.toolEvents[0]
        #expect(te.name == "command_execution")
        #expect(te.command?.contains("ls -1") == true)
        #expect(te.output?.contains("AGENTS.md") == true)
        #expect(te.exitCode == 0)
    }

    @Test func parseErrorSchema() {
        let output = parser.parse(Self.errorSchema)
        let types = output.rawEvents.compactMap { $0["type"]?.stringValue }
        #expect(types.contains("error"))
        #expect(types.contains("turn.failed"))
        #expect(output.toolEvents.isEmpty)
    }

    @Test func noToolEventsInStructuredOnly() {
        let output = parser.parse(Self.structuredSuccess)
        #expect(output.toolEvents.isEmpty)
    }

    @Test func emptyInput() {
        let output = parser.parse("")
        #expect(output.rawEvents.isEmpty)
        #expect(output.toolEvents.isEmpty)
    }

    @Test func malformedLinesSkipped() {
        let raw = """
        {"type":"thread.started"}
        not-json
        {"type":"turn.started"}
        """
        let output = parser.parse(raw)
        #expect(output.rawEvents.count == 2)
    }

    // MARK: - buildResult()

    @Test func buildResultFromStructuredSuccess() {
        let result = parser.buildResult(from: Self.structuredSuccess)
        #expect(result.provider == .codex)
        #expect(result.events.count >= 3)
        #expect(result.toolEvents.isEmpty)
        #expect(result.error == nil)
    }

    @Test func buildResultFromToolUsing() {
        let result = parser.buildResult(from: Self.toolUsing)
        #expect(result.provider == .codex)
        #expect(result.toolEvents.count == 1)
    }

    // MARK: - Tool call summary

    @Test func toolCallSummaryCountsSuccessfulCommand() {
        let output = parser.parse(Self.toolUsing)
        #expect(output.toolCallSummary.attempted == 1)
        #expect(output.toolCallSummary.succeeded == 1)
        #expect(output.toolCallSummary.rejected == 0)
        #expect(output.toolCallSummary.errored == 0)
    }

    @Test func toolCallSummaryCountsFailedCommand() {
        let raw = """
        {"type":"item.completed","item":{"id":"item_0","type":"command_execution","command":"/bin/zsh -lc 'false'","aggregated_output":"","exit_code":1,"status":"completed"}}
        """
        let output = parser.parse(raw)
        #expect(output.toolCallSummary.attempted == 1)
        #expect(output.toolCallSummary.succeeded == 0)
        #expect(output.toolCallSummary.rejected == 0)
        #expect(output.toolCallSummary.errored == 1)
    }

    @Test func toolCallSummaryMixedCommands() {
        let raw = """
        {"type":"item.completed","item":{"id":"item_0","type":"command_execution","command":"/bin/zsh -lc 'echo ok'","aggregated_output":"ok\\n","exit_code":0,"status":"completed"}}
        {"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"/bin/zsh -lc 'false'","aggregated_output":"","exit_code":1,"status":"completed"}}
        {"type":"item.completed","item":{"id":"item_2","type":"command_execution","command":"/bin/zsh -lc 'ls'","aggregated_output":"file.txt\\n","exit_code":0,"status":"completed"}}
        """
        let output = parser.parse(raw)
        #expect(output.toolCallSummary.attempted == 3)
        #expect(output.toolCallSummary.succeeded == 2)
        #expect(output.toolCallSummary.errored == 1)
        #expect(output.toolCallSummary.rejected == 0)
    }

    @Test func toolCallSummaryEmptyForStructuredOnly() {
        let output = parser.parse(Self.structuredSuccess)
        #expect(output.toolCallSummary.attempted == 0)
        #expect(output.toolCallSummary.succeeded == 0)
    }

    @Test func toolCallSummaryIgnoresStartedEvents() {
        let raw = """
        {"type":"item.started","item":{"id":"item_0","type":"command_execution","command":"/bin/zsh -lc 'ls'","aggregated_output":"","exit_code":null,"status":"in_progress"}}
        {"type":"item.completed","item":{"id":"item_0","type":"command_execution","command":"/bin/zsh -lc 'ls'","aggregated_output":"file.txt\\n","exit_code":0,"status":"completed"}}
        """
        let output = parser.parse(raw)
        #expect(output.toolCallSummary.attempted == 1)
        #expect(output.toolCallSummary.succeeded == 1)
    }

    @Test func buildResultIncludesToolCallSummary() {
        let result = parser.buildResult(from: Self.toolUsing)
        #expect(result.toolCallSummary != nil)
        #expect(result.toolCallSummary?.attempted == 1)
        #expect(result.toolCallSummary?.succeeded == 1)
    }
}
