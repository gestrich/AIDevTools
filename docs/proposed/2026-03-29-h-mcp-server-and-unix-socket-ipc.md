## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | Layer placement for new IPC and MCP components |
| `swift-app-architecture:swift-swiftui` | SwiftUI patterns for Mac app changes |

## Background

The contextual AI chat system (completed 2026-03-29-c) uses a text-convention approach: the app embeds structured output descriptors in the system prompt and parses XML `<app-response>` tags from streaming text. This works but is fragile — no schema enforcement, parsing is brittle, and the AI can produce malformed output.

Both Claude CLI and Codex CLI use MCP as their native tool system. The Anthropic API supports `tool_use` blocks natively. If `ai-dev-tools-kit` exposes an MCP server, all three providers get real tool_use semantics — no XML parsing, no text convention, schema-enforced structured output.

The remaining challenge is that the MCP server (the CLI) cannot see in-memory Mac app state (selected plan, current tab). Rather than the app writing a file the CLI polls, a Unix domain socket provides true request-response IPC: the MCP tool handler connects to the app socket, queries live state, disconnects.

### Architecture

```
Mac App (ContextualChatPanel)
  └── launches Claude CLI with --mcp-config pointing at ai-dev-tools-kit mcp
        └── ai-dev-tools-kit mcp (stdio, JSON-RPC 2.0)
              ├── tools backed by existing CLI commands (plans, evals, etc.)
              └── get_ui_state tool → Unix socket → Mac App IPC server
```

### What changes at each layer

**New in SDKs**: `AppIPCSDK` — stateless Unix socket client for querying the Mac app
**New in Apps (CLI)**: `MCPCommand` — MCP server over stdio, tool handlers
**New in Apps (Mac)**: `AppIPCServer` — Unix socket server exposing live UI state
**Simplified in Apps (Mac)**: `ViewChatContext`, `PlansChatContext`, `ContextualChatPanel` — drop response routing
**Removed from SDKs**: `AIResponseDescriptor`, `AIResponseHandling`, `AIResponseRouter`, `StructuredOutputParser`
**Removed from Features**: `responseDescriptors` in `SendChatMessageUseCase.Options`
**Removed from Apps (Mac)**: `SystemPromptBuilder`, `responseHandler` in `ChatModel`

### MCP Swift SDK

Use the official `modelcontextprotocol/swift-sdk` package for MCP server/client protocol implementation.

## Phases

## - [x] Phase 1: AppIPCSDK — Unix domain socket client

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Placed `AppIPCSDK` in the SDKs layer as a stateless `Sendable` struct per architecture rules. Used POSIX socket APIs directly (Darwin) to keep the implementation dependency-free. Error cases are `LocalizedError` so MCP tool handlers can surface descriptive messages to Claude.

**Skills to read**: `swift-app-architecture:swift-architecture`

Add a new SDK target `AppIPCSDK` with a stateless client for querying the Mac app over a Unix domain socket.

**Socket path**: `~/Library/Application Support/AIDevTools/app.sock`

**Protocol**: Newline-delimited JSON over the socket. Request and response are single JSON objects.

**Request/response types:**

```swift
public struct IPCRequest: Codable, Sendable {
    public let query: String  // e.g. "getUIState"
}

public struct IPCUIState: Codable, Sendable {
    public let selectedPlanName: String?
    public let currentTab: String?
}
```

**`AppIPCClient`** (stateless `Sendable` struct):

```swift
public struct AppIPCClient: Sendable {
    public func getUIState() async throws -> IPCUIState
}
```

Opens the socket, sends request, reads response, closes. If the socket file does not exist or connection fails, throw a descriptive error so the MCP tool can return a helpful message to Claude ("App is not running").

**Files to create:**
- `AIDevToolsKit/Sources/SDKs/AppIPCSDK/AppIPCClient.swift`
- `AIDevToolsKit/Sources/SDKs/AppIPCSDK/IPCRequest.swift`
- `AIDevToolsKit/Sources/SDKs/AppIPCSDK/IPCUIState.swift`

**Package.swift**: Add `AppIPCSDK` target; add as dependency to `AIDevToolsKitCLI`.

## - [x] Phase 2: AppIPCServer in Mac app

**Skills used**: `swift-app-architecture:swift-architecture`, `swift-app-architecture:swift-swiftui`
**Principles applied**: Kept `AppIPCServer` internal to `AIDevToolsKitMac` (no `public`) and started it from `AIDevToolsKitMacEntryView` via `.task` rather than the outer `AIDevToolsApp` struct, which cannot see internal types. `currentTab` and `selectedPlanName` are read from `UserDefaults` directly (the backing store for `@AppStorage`), avoiding the need to pass model references into the server. Static `nonisolated` helpers handle the blocking accept loop off the main actor.

**Skills to read**: `swift-app-architecture:swift-architecture`, `swift-app-architecture:swift-swiftui`

Add `AppIPCServer` to the Mac app that listens on the Unix domain socket and responds to queries with live UI state.

**`AppIPCServer`** (`@MainActor final class`):
- Starts listening on `app.sock` at app launch
- Handles `getUIState` query: returns selected plan name and current tab from `@AppStorage` / observable models
- Removes stale socket file on start, cleans up on stop

**Ownership**: `AIDevToolsApp` (the `@main` struct) creates and starts `AppIPCServer` via `.task`. It holds a reference to `WorkspaceModel` to read current state.

**Files to create:**
- `AIDevToolsKitMac/IPC/AppIPCServer.swift`

**Files to modify:**
- `AIDevToolsKitMac/AIDevToolsApp.swift` — start `AppIPCServer` in `.task`

## - [ ] Phase 3: MCPCommand in ai-dev-tools-kit CLI

**Skills to read**: `swift-app-architecture:swift-architecture`

Add `MCPCommand` as a subcommand of `ai-dev-tools-kit`. When invoked, it starts an MCP server over stdio using `modelcontextprotocol/swift-sdk`, exposing the following tools:

**Tools backed by existing CLI logic:**

| Tool | Maps to | Description |
|------|---------|-------------|
| `list_plans` | `MarkdownPlannerCommand list` | Returns plan names and completion status |
| `get_plan_details` | `MarkdownPlannerCommand inspect` | Returns phases and content for a named plan |
| `select_plan` | deep link write | Writes `aidevtools://plans/select/{name}` to `deeplink.txt` |
| `navigate_to_tab` | deep link write | Writes `aidevtools://tab/{name}` to `deeplink.txt` |
| `reload_plans` | deep link write | Writes `aidevtools://plans/reload` to `deeplink.txt` |

**Tool backed by IPC:**

| Tool | Description |
|------|-------------|
| `get_ui_state` | Connects to `AppIPCSDK`, returns selected plan and current tab |

Tool handlers call existing use cases directly rather than shelling out to CLI subcommands. Each handler is a simple `async throws` function.

**Files to create:**
- `AIDevToolsKit/Sources/Apps/AIDevToolsKitCLI/MCPCommand.swift`

**Files to modify:**
- `AIDevToolsKit/Sources/Apps/AIDevToolsKitCLI/EntryPoint.swift` — add `MCPCommand` to subcommands (alphabetical)
- `AIDevToolsKit/Package.swift` — add `modelcontextprotocol/swift-sdk` dependency

## - [ ] Phase 4: Mac app integration — swap XML approach for MCP

**Skills to read**: `swift-app-architecture:swift-swiftui`

Update `ContextualChatPanel` to launch Claude CLI with `--mcp-config` pointing at `ai-dev-tools-kit mcp` instead of building a structured system prompt.

**`ContextualChatPanel` changes:**
- Build `--mcp-config` JSON at chat startup pointing to `ai-dev-tools-kit mcp`
- Pass via `AIClientOptions` (new `mcpConfig` field, or via extra CLI args)
- Remove `ViewChatContext.responseRouter` requirement from the protocol

**`ViewChatContext` simplification:**
```swift
@MainActor
protocol ViewChatContext: AnyObject {
    var chatContextIdentifier: String { get }
    var chatSystemPrompt: String { get }   // brief context only, no tool descriptors
    var chatWorkingDirectory: String { get }
}
```

**`PlansChatContext` simplification:**
- Remove all route handlers (`selectPlan`, `reloadPlans`, `navigateToTab`, `getViewState`, `getPlanDetails`)
- Only provides `chatSystemPrompt`, `chatWorkingDirectory`, `chatContextIdentifier`

**`SystemPromptBuilder` removal:**
- Delete the file; callers use `ViewChatContext.chatSystemPrompt` directly

**Files to modify:**
- `AIDevToolsKitMac/Views/Chat/ViewChatContext.swift`
- `AIDevToolsKitMac/Views/Chat/ContextualChatPanel.swift`
- `AIDevToolsKitMac/Models/PlansChatContext.swift`
- `AIOutputSDK/AIClient.swift` — add MCP config passthrough to `AIClientOptions`
- `ClaudeCLISDK` — forward MCP config to `--mcp-config` flag

**Files to delete:**
- `AIDevToolsKitMac/Views/Chat/SystemPromptBuilder.swift`

## - [ ] Phase 5: Remove XML structured output infrastructure

**Skills to read**: `swift-app-architecture:swift-architecture`

With MCP handling tool dispatch natively, the XML tag infrastructure is no longer needed.

**Delete from `AIOutputSDK`:**
- `AIResponseDescriptor.swift`
- `AIResponseHandling.swift`
- `AIResponseRouter.swift`
- `StructuredOutputParser.swift`

**Remove from `AIClientOptions`:**
- `responseDescriptors: [AIResponseDescriptor]`

**Remove from `SendChatMessageUseCase.Options`:**
- `responseDescriptors`

**Remove from `ChatModel` / `ChatModelConfiguration`:**
- `responseHandler: (any AIResponseHandling)?`
- Round-trip query handling logic
- `<app-response>` tag stripping

**Update callers**: `MarkdownPlannerModel.makeChatModel()` and `ClaudeChainModel.makeChatModel()` — remove response handler wiring.

## - [ ] Phase 6: Validation

**Skills to read**: `swift-app-architecture:swift-architecture`

**Build verification:**
- Package builds cleanly with no references to deleted types
- All existing tests pass

**New unit tests:**
- `AppIPCClientTests` — mock socket, verify request/response encoding
- `MCPCommandTests` — tool handler logic (list_plans returns correct shape, get_ui_state handles app-not-running gracefully)

**Manual testing:**
1. Launch app, open Plans tab — chat panel appears
2. Ask "what plan am I looking at?" — MCP `get_ui_state` fires, AI answers with live selection
3. Ask "select plan X" — `deeplink.txt` written, sidebar updates
4. Ask "take me to evals" — tab switches
5. Kill app, ask question — AI receives "app not running" and handles gracefully
6. Verify Codex CLI also works by switching provider and repeating steps 2–4

**Regression checks:**
- Execution/iteration chat in `MarkdownPlannerDetailView` unchanged
- `ClaudeChainModel` chat unchanged
- PRRadar unaffected
