import AppIPCSDK
import ArgumentParser
import ClaudeChainFeature
import DataPathsService
import Foundation
import MCP
import MarkdownPlannerFeature
import MarkdownPlannerService
import RepositorySDK

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Start MCP server over stdio"
    )

    func run() async throws {
        let server = Server(
            name: "ai-dev-tools-kit",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: Self.allTools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            try await Self.handleCallTool(params)
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    // MARK: - Tool definitions

    private static let allTools: [Tool] = [
        Tool(
            name: "get_chain_status",
            description: "Returns task completion status for a named chain project in the current repository",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Chain project name to retrieve status for")
                    ])
                ]),
                "required": .array([.string("name")])
            ])
        ),
        Tool(
            name: "get_plan_details",
            description: "Returns phases and content for a named plan",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Plan name to retrieve details for")
                    ])
                ]),
                "required": .array([.string("name")])
            ])
        ),
        Tool(
            name: "get_ui_state",
            description: "Returns current UI state of the AIDevTools Mac app: selected plan and current tab",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        ),
        Tool(
            name: "list_plans",
            description: "Returns plan names and completion status from the current repository",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        ),
        Tool(
            name: "navigate_to_tab",
            description: "Navigates the AIDevTools Mac app to the specified tab",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "tab": .object([
                        "type": .string("string"),
                        "description": .string("Tab name to navigate to")
                    ])
                ]),
                "required": .array([.string("tab")])
            ])
        ),
        Tool(
            name: "reload_plans",
            description: "Triggers the AIDevTools Mac app to reload the plans list",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        ),
        Tool(
            name: "select_plan",
            description: "Selects a plan in the AIDevTools Mac app sidebar",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Plan name to select")
                    ])
                ]),
                "required": .array([.string("name")])
            ])
        ),
    ]

    // MARK: - Tool dispatch

    static func handleCallTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "get_chain_status":
            return try await handleGetChainStatus(params.arguments ?? [:])
        case "get_plan_details":
            return try await handleGetPlanDetails(params.arguments ?? [:])
        case "get_ui_state":
            return try await handleGetUIState()
        case "list_plans":
            return try await handleListPlans()
        case "navigate_to_tab":
            return try await handleNavigateToTab(params.arguments ?? [:])
        case "reload_plans":
            return try await handleReloadPlans()
        case "select_plan":
            return try await handleSelectPlan(params.arguments ?? [:])
        default:
            return .init(content: [.text(text: "Unknown tool: \(params.name)", annotations: nil, _meta: nil)], isError: true)
        }
    }

    // MARK: - Tool handlers

    private static func handleListPlans() async throws -> CallTool.Result {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let proposedDir = cwd.appendingPathComponent(MarkdownPlannerRepoSettings.defaultProposedDirectory)
        let plans = await LoadPlansUseCase(proposedDirectory: proposedDir).run()

        if plans.isEmpty {
            return .init(content: [.text(text: "No plans found in \(proposedDir.path)", annotations: nil, _meta: nil)], isError: false)
        }

        let text = plans
            .map { "\($0.name): \($0.completedPhases)/\($0.totalPhases) phases complete" }
            .joined(separator: "\n")
        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    }

    private static func handleGetChainStatus(_ arguments: [String: Value]) async throws -> CallTool.Result {
        guard let nameValue = arguments["name"], let name = nameValue.stringValue else {
            return .init(content: [.text(text: "Missing required argument: name", annotations: nil, _meta: nil)], isError: true)
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        do {
            let chains = try await ListChainsUseCase().run(options: .init(repoPath: cwd))
            guard let chain = chains.first(where: { $0.name == name }) else {
                return .init(content: [.text(text: "Chain '\(name)' not found", annotations: nil, _meta: nil)], isError: false)
            }
            var lines = [
                "Chain: \(chain.name)",
                "Progress: \(chain.completedTasks)/\(chain.totalTasks) tasks completed (\(chain.pendingTasks) pending)",
                "",
                "Tasks:"
            ]
            for task in chain.tasks {
                let marker = task.isCompleted ? "✓" : "○"
                lines.append("  \(marker) \(task.description)")
            }
            return .init(content: [.text(text: lines.joined(separator: "\n"), annotations: nil, _meta: nil)], isError: false)
        } catch {
            return .init(content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)], isError: true)
        }
    }

    private static func handleGetPlanDetails(_ arguments: [String: Value]) async throws -> CallTool.Result {
        guard let nameValue = arguments["name"], let name = nameValue.stringValue else {
            return .init(content: [.text(text: "Missing required argument: name", annotations: nil, _meta: nil)], isError: true)
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let proposedDir = cwd.appendingPathComponent(MarkdownPlannerRepoSettings.defaultProposedDirectory)
        do {
            let content = try await GetPlanDetailsUseCase(proposedDirectory: proposedDir).run(planName: name)
            return .init(content: [.text(text: content, annotations: nil, _meta: nil)], isError: false)
        } catch {
            return .init(content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)], isError: true)
        }
    }

    private static func handleSelectPlan(_ arguments: [String: Value]) async throws -> CallTool.Result {
        guard let nameValue = arguments["name"], let name = nameValue.stringValue else {
            return .init(content: [.text(text: "Missing required argument: name", annotations: nil, _meta: nil)], isError: true)
        }

        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        try writeDeepLink("aidevtools://plans/select/\(encoded)")
        return .init(content: [.text(text: "Selected plan: \(name)", annotations: nil, _meta: nil)], isError: false)
    }

    private static func handleNavigateToTab(_ arguments: [String: Value]) async throws -> CallTool.Result {
        guard let tabValue = arguments["tab"], let tab = tabValue.stringValue else {
            return .init(content: [.text(text: "Missing required argument: tab", annotations: nil, _meta: nil)], isError: true)
        }

        let encoded = tab.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tab
        try writeDeepLink("aidevtools://tab/\(encoded)")
        return .init(content: [.text(text: "Navigated to tab: \(tab)", annotations: nil, _meta: nil)], isError: false)
    }

    private static func handleReloadPlans() async throws -> CallTool.Result {
        try writeDeepLink("aidevtools://plans/reload")
        return .init(content: [.text(text: "Plans reload triggered", annotations: nil, _meta: nil)], isError: false)
    }

    private static func handleGetUIState() async throws -> CallTool.Result {
        do {
            let state = try await AppIPCClient().getUIState()
            let text = """
                Current tab: \(state.currentTab ?? "unknown")
                Selected chain: \(state.selectedChainName ?? "none")
                Selected plan: \(state.selectedPlanName ?? "none")
                """
            return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
        } catch {
            return .init(
                content: [.text(text: "App is not running or unavailable: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: false
            )
        }
    }

    // MARK: - Deep link helper

    private static func writeDeepLink(_ urlString: String) throws {
        let fileURL = DataPathsService.deepLinkFileURL
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try urlString.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
