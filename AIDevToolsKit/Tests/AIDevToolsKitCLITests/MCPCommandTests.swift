@testable import AIDevToolsKitCLI
import Foundation
import MCP
import Testing

@Suite("MCPCommand")
struct MCPCommandTests {

    @Test("MCPCommand has correct command name")
    func commandName() {
        #expect(MCPCommand.configuration.commandName == "mcp")
    }

    // MARK: - list_plans tool

    @Test("list_plans returns non-error result with text content")
    func listPlansReturnsCorrectShape() async throws {
        let params = CallTool.Parameters(name: "list_plans")
        let result = try await MCPCommand.handleCallTool(params)
        #expect(result.isError != true)
        #expect(!result.content.isEmpty)
    }

    // MARK: - get_ui_state tool

    @Test("get_ui_state returns non-error result when app is not running")
    func getUIStateHandlesAppNotRunning() async throws {
        let socketPath = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIDevTools/app.sock")
            .path
        guard !FileManager.default.fileExists(atPath: socketPath) else {
            return  // App is running — skip this case
        }
        let params = CallTool.Parameters(name: "get_ui_state")
        let result = try await MCPCommand.handleCallTool(params)
        #expect(result.isError != true)
        guard case .text(let text, _, _) = result.content.first else {
            Issue.record("Expected text content in get_ui_state result")
            return
        }
        #expect(text.contains("not running") || text.contains("unavailable"))
    }
}
