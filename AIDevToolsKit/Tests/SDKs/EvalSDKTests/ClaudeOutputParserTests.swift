import Testing
@testable import EvalSDK
@testable import EvalService

@Suite("ClaudeOutputParser")
struct ClaudeOutputParserTests {

    let parser = ClaudeOutputParser()

    // MARK: - Fixtures

    static let structuredSuccess = """
    {"type":"system","subtype":"init","session_id":"14c610ee-0000-0000-0000-000000000001"}
    {"type":"assistant","message":{"id":"msg_001","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_001","name":"StructuredOutput","input":{"result":"PROBE_STRUCTURED_OK"}}]}}
    {"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_001","type":"tool_result","content":"Structured output provided successfully"}]}}
    {"type":"result","subtype":"success","is_error":false,"duration_ms":5592,"duration_api_ms":4911,"num_turns":2,"total_cost_usd":0.0544,"structured_output":{"result":"PROBE_STRUCTURED_OK"}}
    """

    static let toolUsing = """
    {"type":"system","subtype":"init","session_id":"e48d2ba1-0000-0000-0000-000000000002"}
    {"type":"assistant","message":{"id":"msg_002","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_002","name":"Bash","input":{"command":"ls | head -3","description":"List first 3 directory entries"}}]}}
    {"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_002","type":"tool_result","content":"AGENTS.md\\nAmazonWebServices\\nAviationMathUtils","is_error":false}]}}
    {"type":"assistant","message":{"id":"msg_003","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_003","name":"StructuredOutput","input":{"result":"First 3 entries: AGENTS.md, AmazonWebServices, AviationMathUtils."}}]}}
    {"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_003","type":"tool_result","content":"Structured output provided successfully"}]}}
    {"type":"result","subtype":"success","is_error":false,"duration_ms":10073,"duration_api_ms":9066,"num_turns":3,"total_cost_usd":0.0744,"structured_output":{"result":"First 3 entries: AGENTS.md, AmazonWebServices, AviationMathUtils."}}
    """

    static let errorImpossibleSchema = """
    {"type":"system","subtype":"init","session_id":"df6e7978-0000-0000-0000-000000000003"}
    {"type":"assistant","message":{"id":"msg_004","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_004","name":"StructuredOutput","input":{"result":"ALPHA"}}]}}
    {"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"Output does not match required schema: /result: must match pattern \\"^BETA$\\"","is_error":true,"tool_use_id":"toolu_004"}]}}
    {"type":"assistant","message":{"id":"msg_005","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_005","name":"StructuredOutput","input":{"result":"ALPHA"}}]}}
    {"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"Output does not match required schema: /result: must match pattern \\"^BETA$\\"","is_error":true,"tool_use_id":"toolu_005"}]}}
    {"type":"result","subtype":"error_max_structured_output_retries","duration_ms":29497,"duration_api_ms":26699,"is_error":true,"num_turns":9,"total_cost_usd":0.1631,"errors":["Failed to provide valid structured output after 5 attempts"]}
    """

    // MARK: - parse()

    @Test func parseStructuredSuccess() {
        let output = parser.parse(Self.structuredSuccess)
        #expect(output.rawEvents.count >= 3)
        let resultEvent = output.resultEvent
        #expect(resultEvent != nil)
        #expect(resultEvent?.isError == false)
        #expect(resultEvent?.structuredOutput?["result"]?.stringValue == "PROBE_STRUCTURED_OK")
        #expect(resultEvent?.durationMs == 5592)
        #expect(resultEvent?.totalCostUsd != nil)
        let cost = resultEvent!.totalCostUsd!
        #expect(abs(cost - 0.0544) < 0.001)
    }

    @Test func parseToolUsing() {
        let output = parser.parse(Self.toolUsing)
        #expect(output.toolEvents.count == 1)
        let te = output.toolEvents[0]
        #expect(te.name == "Bash")
        #expect(te.command == "ls | head -3")
        #expect(te.inputKeys.contains("command"))
    }

    @Test func structuredOutputToolFiltered() {
        let output = parser.parse(Self.structuredSuccess)
        #expect(output.toolEvents.isEmpty)
    }

    @Test func parseErrorImpossibleSchema() {
        let output = parser.parse(Self.errorImpossibleSchema)
        let resultEvent = output.resultEvent
        #expect(resultEvent != nil)
        #expect(resultEvent?.isError == true)
        #expect(resultEvent?.subtype == "error_max_structured_output_retries")
        if case .array(let errors) = resultEvent?.errors {
            let first = errors.first?.stringValue ?? ""
            #expect(first.contains("Failed to provide valid structured output"))
        } else {
            Issue.record("Expected errors to be an array")
        }
    }

    // MARK: - findResultEvent (via parse)

    @Test func findResultEventReturnsLast() {
        let raw = """
        {"type":"system"}
        {"type":"assistant","message":{"content":[]}}
        {"type":"result","is_error":false,"subtype":"first"}
        {"type":"result","is_error":false,"subtype":"second"}
        """
        let output = parser.parse(raw)
        #expect(output.resultEvent?.subtype == "second")
    }

    @Test func findResultEventMissing() {
        let raw = """
        {"type":"system"}
        {"type":"assistant","message":{"content":[]}}
        """
        let output = parser.parse(raw)
        #expect(output.resultEvent == nil)
    }

    // MARK: - Edge cases

    @Test func emptyInput() {
        let output = parser.parse("")
        #expect(output.rawEvents.isEmpty)
        #expect(output.toolEvents.isEmpty)
        #expect(output.resultEvent == nil)
    }

    @Test func malformedLinesSkipped() {
        let raw = """
        {"type":"system"}
        garbage
        {"type":"result","is_error":false}
        """
        let output = parser.parse(raw)
        #expect(output.rawEvents.count == 2)
    }

    @Test func multipleToolCallsExtracted() {
        let raw = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/a.txt"}},{"type":"tool_use","name":"Bash","input":{"command":"echo hi"}},{"type":"tool_use","name":"StructuredOutput","input":{"result":"x"}}]}}
        """
        let output = parser.parse(raw)
        #expect(output.toolEvents.count == 2)
        #expect(output.toolEvents[0].name == "Read")
        #expect(output.toolEvents[1].name == "Bash")
        #expect(output.toolEvents[1].command == "echo hi")
    }

    // MARK: - Tool call summary

    @Test func toolCallSummaryCountsSuccessfulCalls() {
        let output = parser.parse(Self.toolUsing)
        #expect(output.toolCallSummary.attempted == 1)
        #expect(output.toolCallSummary.succeeded == 1)
        #expect(output.toolCallSummary.rejected == 0)
        #expect(output.toolCallSummary.errored == 0)
    }

    @Test func toolCallSummaryCountsRejectedCalls() {
        let raw = """
        {"type":"assistant","message":{"id":"msg_010","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_010","name":"Edit","input":{"file_path":"/a.swift","old_string":"x","new_string":"y"}}]}}
        {"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_010","type":"tool_result","content":"This command requires approval","is_error":true}]}}
        {"type":"result","is_error":false,"subtype":"success","structured_output":{"result":"done"}}
        """
        let output = parser.parse(raw)
        #expect(output.toolCallSummary.attempted == 1)
        #expect(output.toolCallSummary.succeeded == 0)
        #expect(output.toolCallSummary.rejected == 1)
        #expect(output.toolCallSummary.errored == 0)
    }

    @Test func toolCallSummaryCountsErrors() {
        let raw = """
        {"type":"assistant","message":{"id":"msg_011","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_011","name":"Bash","input":{"command":"false"}}]}}
        {"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_011","type":"tool_result","content":"exit code 1","is_error":true}]}}
        {"type":"result","is_error":false,"subtype":"success","structured_output":{"result":"failed"}}
        """
        let output = parser.parse(raw)
        #expect(output.toolCallSummary.attempted == 1)
        #expect(output.toolCallSummary.succeeded == 0)
        #expect(output.toolCallSummary.rejected == 0)
        #expect(output.toolCallSummary.errored == 1)
    }

    @Test func toolCallSummaryMultipleMixed() {
        let raw = """
        {"type":"assistant","message":{"id":"msg_020","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_020","name":"Read","input":{"file_path":"/a.txt"}},{"type":"tool_use","id":"toolu_021","name":"Edit","input":{"file_path":"/b.txt","old_string":"x","new_string":"y"}}]}}
        {"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_020","type":"tool_result","content":"file contents"},{"tool_use_id":"toolu_021","type":"tool_result","content":"This command requires approval","is_error":true}]}}
        {"type":"result","is_error":false,"subtype":"success","structured_output":{"result":"partial"}}
        """
        let output = parser.parse(raw)
        #expect(output.toolCallSummary.attempted == 2)
        #expect(output.toolCallSummary.succeeded == 1)
        #expect(output.toolCallSummary.rejected == 1)
        #expect(output.toolCallSummary.errored == 0)
    }

    @Test func toolCallSummaryEmptyForStructuredOnly() {
        let output = parser.parse(Self.structuredSuccess)
        #expect(output.toolCallSummary.attempted == 0)
        #expect(output.toolCallSummary.succeeded == 0)
    }

    @Test func toolCallOutputPopulated() {
        let output = parser.parse(Self.toolUsing)
        #expect(output.toolEvents.count == 1)
        #expect(output.toolEvents[0].output != nil)
        #expect(output.toolEvents[0].output?.contains("AGENTS.md") == true)
    }

    @Test func buildResultIncludesToolCallSummary() {
        let result = parser.buildResult(from: Self.toolUsing)
        #expect(result.toolCallSummary != nil)
        #expect(result.toolCallSummary?.attempted == 1)
        #expect(result.toolCallSummary?.succeeded == 1)
    }

    // MARK: - Skill name extraction

    @Test func skillToolCallExtractsSkillName() {
        // Arrange
        let raw = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_030","name":"Skill","input":{"skill":"map-layer"}}]}}
        {"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_030","type":"tool_result","content":"Skill loaded"}]}}
        """

        // Act
        let output = parser.parse(raw)

        // Assert
        #expect(output.toolEvents.count == 1)
        #expect(output.toolEvents[0].name == "Skill")
        #expect(output.toolEvents[0].skillName == "map-layer")
        #expect(output.toolEvents[0].filePath == nil)
    }

    @Test func skillToolCallWithMissingInputHasNilSkillName() {
        // Arrange
        let raw = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_031","name":"Skill","input":{}}]}}
        """

        // Act
        let output = parser.parse(raw)

        // Assert
        #expect(output.toolEvents.count == 1)
        #expect(output.toolEvents[0].skillName == nil)
    }

    // MARK: - File path extraction

    @Test func readToolCallExtractsFilePath() {
        // Arrange
        let raw = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_032","name":"Read","input":{"file_path":"/Users/bill/.claude/skills/map-layer/feature-layers.md"}}]}}
        {"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_032","type":"tool_result","content":"file contents here"}]}}
        """

        // Act
        let output = parser.parse(raw)

        // Assert
        #expect(output.toolEvents.count == 1)
        #expect(output.toolEvents[0].name == "Read")
        #expect(output.toolEvents[0].filePath == "/Users/bill/.claude/skills/map-layer/feature-layers.md")
        #expect(output.toolEvents[0].skillName == nil)
    }

    @Test func readToolCallWithMissingInputHasNilFilePath() {
        // Arrange
        let raw = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_033","name":"Read","input":{}}]}}
        """

        // Act
        let output = parser.parse(raw)

        // Assert
        #expect(output.toolEvents.count == 1)
        #expect(output.toolEvents[0].filePath == nil)
    }

    @Test func nonSkillNonReadToolHasNilSkillNameAndFilePath() {
        // Arrange
        let raw = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_034","name":"Grep","input":{"pattern":"TODO","path":"/src"}}]}}
        """

        // Act
        let output = parser.parse(raw)

        // Assert
        #expect(output.toolEvents.count == 1)
        #expect(output.toolEvents[0].name == "Grep")
        #expect(output.toolEvents[0].skillName == nil)
        #expect(output.toolEvents[0].filePath == nil)
    }

    // MARK: - buildResult()

    @Test func buildResultStructuredSuccess() {
        let result = parser.buildResult(from: Self.structuredSuccess)
        #expect(result.provider == .claude)
        #expect(result.error == nil)
        #expect(result.structuredOutput?["result"]?.stringValue == "PROBE_STRUCTURED_OK")
        #expect(result.resultText == "PROBE_STRUCTURED_OK")
        #expect(result.metrics?.durationMs == 5592)
        #expect(result.metrics?.turns == 2)
    }

    @Test func buildResultErrorSetsProviderError() {
        let result = parser.buildResult(from: Self.errorImpossibleSchema)
        #expect(result.provider == .claude)
        #expect(result.error != nil)
        #expect(result.error?.subtype == "error_max_structured_output_retries")
    }

    @Test func buildResultMissingResultEventSetsError() {
        let raw = """
        {"type":"system"}
        {"type":"assistant","message":{"content":[]}}
        """
        let result = parser.buildResult(from: raw)
        #expect(result.error != nil)
        #expect(result.error?.subtype == "missing_result")
    }
}
