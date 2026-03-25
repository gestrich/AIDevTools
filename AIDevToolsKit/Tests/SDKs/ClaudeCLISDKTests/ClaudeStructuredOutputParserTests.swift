import CLISDK
import Testing
@testable import ClaudeCLISDK

struct TestOutput: Codable, Sendable {
    let repoId: String
    let interpretedRequest: String
}

struct SimpleResult: Codable, Sendable {
    let result: String
}

private func makeResult(stdout: String, exitCode: Int32 = 0, stderr: String = "") -> ExecutionResult {
    ExecutionResult(exitCode: exitCode, stdout: stdout, stderr: stderr, duration: 0)
}

@Suite("ClaudeStructuredOutputParser")
struct ClaudeStructuredOutputParserTests {

    let parser = ClaudeStructuredOutputParser()

    // MARK: - Fixtures

    static let successWithStructuredOutput = """
    {"type":"system","subtype":"init","session_id":"14c610ee-0000-0000-0000-000000000001"}
    {"type":"assistant","message":{"id":"msg_001","type":"message","role":"assistant","content":[{"type":"text","text":"Matching repository..."}]}}
    {"type":"result","subtype":"success","is_error":false,"duration_ms":5592,"num_turns":2,"total_cost_usd":0.0544,"session_id":"14c610ee-0000-0000-0000-000000000001","structured_output":{"repoId":"my-app","interpretedRequest":"Fix the login bug"}}
    """

    static let successSimpleResult = """
    {"type":"result","subtype":"success","is_error":false,"duration_ms":1500,"num_turns":1,"total_cost_usd":0.001,"structured_output":{"result":"PROBE_STRUCTURED_OK"}}
    """

    static let errorMaxRetries = """
    {"type":"assistant","message":{"id":"msg_004","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_004","name":"StructuredOutput","input":{"result":"ALPHA"}}]}}
    {"type":"result","subtype":"error_max_structured_output_retries","duration_ms":29497,"is_error":true,"num_turns":9,"total_cost_usd":0.1631,"errors":["Failed to provide valid structured output after 5 attempts"]}
    """

    static let errorDuringExecution = """
    {"type":"result","subtype":"error_during_execution","is_error":true,"duration_ms":500,"num_turns":1,"errors":["Something went wrong"]}
    """

    static let noResultEvent = """
    {"type":"system","subtype":"init","session_id":"abc123"}
    {"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}
    """

    static let resultWithoutStructuredOutput = """
    {"type":"result","subtype":"success","is_error":false,"duration_ms":1000,"num_turns":1}
    """

    // MARK: - parse() success

    @Test func parseStructuredOutputSuccess() throws {
        let output = try parser.parse(TestOutput.self, from: makeResult(stdout: Self.successWithStructuredOutput))
        #expect(output.value.repoId == "my-app")
        #expect(output.value.interpretedRequest == "Fix the login bug")
        #expect(output.resultEvent.isError == false)
        #expect(output.resultEvent.durationMs == 5592)
        #expect(output.resultEvent.numTurns == 2)
        #expect(output.resultEvent.sessionId == "14c610ee-0000-0000-0000-000000000001")
    }

    @Test func parseSimpleResult() throws {
        let output = try parser.parse(SimpleResult.self, from: makeResult(stdout: Self.successSimpleResult))
        #expect(output.value.result == "PROBE_STRUCTURED_OK")
        #expect(output.resultEvent.totalCostUsd != nil)
        let cost = output.resultEvent.totalCostUsd!
        #expect(abs(cost - 0.001) < 0.0001)
    }

    // MARK: - parse() errors

    @Test func parseThrowsOnErrorResult() {
        #expect(throws: ClaudeStructuredOutputError.self) {
            try parser.parse(SimpleResult.self, from: makeResult(stdout: Self.errorMaxRetries))
        }
    }

    @Test func parseThrowsOnExecutionError() {
        #expect(throws: ClaudeStructuredOutputError.self) {
            try parser.parse(SimpleResult.self, from: makeResult(stdout: Self.errorDuringExecution))
        }
    }

    @Test func parseThrowsOnNoResultEvent() {
        #expect(throws: ClaudeStructuredOutputError.self) {
            try parser.parse(SimpleResult.self, from: makeResult(stdout: Self.noResultEvent))
        }
    }

    @Test func parseThrowsOnMissingStructuredOutput() {
        #expect(throws: ClaudeStructuredOutputError.self) {
            try parser.parse(SimpleResult.self, from: makeResult(stdout: Self.resultWithoutStructuredOutput))
        }
    }

    @Test func parseThrowsOnTypeMismatch() {
        let wrongType = """
        {"type":"result","subtype":"success","is_error":false,"structured_output":{"unexpected":"fields"}}
        """
        #expect(throws: ClaudeStructuredOutputError.self) {
            try parser.parse(TestOutput.self, from: makeResult(stdout: wrongType))
        }
    }

    @Test func parseThrowsOnMissingSubtype() {
        let noSubtype = """
        {"type":"result","is_error":false,"structured_output":{"result":"ok"}}
        """
        #expect(throws: ClaudeStructuredOutputError.self) {
            try parser.parse(SimpleResult.self, from: makeResult(stdout: noSubtype))
        }
    }

    // MARK: - findResultEvent

    @Test func findResultEventReturnsLast() throws {
        let raw = """
        {"type":"result","is_error":false,"subtype":"first","duration_ms":100}
        {"type":"result","is_error":false,"subtype":"second","duration_ms":200}
        """
        let event = try parser.findResultEvent(in: raw)
        #expect(event.subtype == "second")
        #expect(event.durationMs == 200)
    }

    @Test func findResultEventSkipsNonResultLines() throws {
        let raw = """
        {"type":"system","subtype":"init"}
        {"type":"assistant","message":{"content":[]}}
        garbage line
        {"type":"result","is_error":false,"subtype":"success","duration_ms":1000}
        """
        let event = try parser.findResultEvent(in: raw)
        #expect(event.subtype == "success")
    }

    @Test func findResultEventThrowsOnEmpty() {
        #expect(throws: ClaudeStructuredOutputError.self) {
            try parser.findResultEvent(in: "")
        }
    }

    @Test func findResultEventThrowsOnNoResult() {
        #expect(throws: ClaudeStructuredOutputError.self) {
            try parser.findResultEvent(in: Self.noResultEvent)
        }
    }

    // MARK: - Error details

    @Test func errorResultPreservesSubtype() throws {
        do {
            _ = try parser.parse(SimpleResult.self, from: makeResult(stdout: Self.errorMaxRetries))
            Issue.record("Expected error to be thrown")
        } catch let error as ClaudeStructuredOutputError {
            if case .resultError(let resultEvent) = error {
                #expect(resultEvent.subtype == "error_max_structured_output_retries")
            } else {
                Issue.record("Expected resultError case, got \(error)")
            }
        }
    }

    @Test func errorResultPreservesErrors() throws {
        do {
            _ = try parser.parse(SimpleResult.self, from: makeResult(stdout: Self.errorMaxRetries))
            Issue.record("Expected error to be thrown")
        } catch let error as ClaudeStructuredOutputError {
            if case .resultError(let resultEvent) = error {
                #expect(resultEvent.errors != nil)
                #expect(resultEvent.sessionId == nil)
                #expect(resultEvent.numTurns == 9)
            } else {
                Issue.record("Expected resultError case")
            }
        }
    }

    @Test func errorResultIncludesDiagnostics() throws {
        do {
            _ = try parser.parse(SimpleResult.self, from: makeResult(stdout: Self.errorMaxRetries))
            Issue.record("Expected error to be thrown")
        } catch let error as ClaudeStructuredOutputError {
            let description = error.errorDescription ?? ""
            #expect(description.contains("turns=9"))
            #expect(description.contains("is_error=true"))
        }
    }

    @Test func noResultEventIncludesProcessDiagnostics() throws {
        do {
            _ = try parser.parse(
                SimpleResult.self,
                from: ExecutionResult(
                    exitCode: 137,
                    stdout: Self.noResultEvent,
                    stderr: "killed by signal 9",
                    duration: 5.0
                )
            )
            Issue.record("Expected error to be thrown")
        } catch let error as ClaudeStructuredOutputError {
            let description = error.errorDescription ?? ""
            #expect(description.contains("exit=137"))
            #expect(description.contains("killed by signal 9"))
            #expect(description.contains("stdout="))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Edge cases

    @Test func handlesLeadingWhitespace() throws {
        let raw = """
            {"type":"result","subtype":"success","is_error":false,"structured_output":{"result":"ok"}}
        """
        let output = try parser.parse(SimpleResult.self, from: makeResult(stdout: raw))
        #expect(output.value.result == "ok")
    }

    @Test func handlesNestedStructuredOutput() throws {
        struct Nested: Codable, Sendable {
            let phases: [Phase]
            struct Phase: Codable, Sendable {
                let description: String
                let status: String
            }
        }

        let raw = """
        {"type":"result","subtype":"success","is_error":false,"structured_output":{"phases":[{"description":"Setup","status":"completed"},{"description":"Build","status":"pending"}]}}
        """
        let output = try parser.parse(Nested.self, from: makeResult(stdout: raw))
        #expect(output.value.phases.count == 2)
        #expect(output.value.phases[0].description == "Setup")
        #expect(output.value.phases[0].status == "completed")
        #expect(output.value.phases[1].status == "pending")
    }
}
