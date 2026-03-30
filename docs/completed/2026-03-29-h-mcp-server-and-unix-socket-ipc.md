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

## - [x] Phase 3: MCPCommand in ai-dev-tools-kit CLI

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Placed `MCPCommand` in the Apps layer (CLI). Used `modelcontextprotocol/swift-sdk` for the stdio MCP server. Tool handlers call `LoadPlansUseCase` and `AppIPCClient` directly (not shelling out to CLI subcommands). Deep link tools write to `~/Library/Application Support/AIDevTools/deeplink.txt`, matching the existing `DeepLinkWatcher` path. `arguments` on `CallTool.Parameters` is `[String: Value]?` (optional), so handlers unwrap with `?? [:]` at the call site.

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

## - [x] Phase 4: Mac app integration — swap XML approach for MCP

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: Threaded `mcpConfigPath` from `AIClientOptions` through `ClaudeProvider`, `SendChatMessageUseCase`, `ChatModelConfiguration`, and `ChatModel`. `ContextualChatPanel` writes the MCP config JSON to a stable path in Application Support and passes it to `ChatModelConfiguration`. `ViewChatContext` loses the `responseRouter` requirement; `PlansChatContext` drops all route handlers and only provides the three protocol properties. `SystemPromptBuilder` is deleted; `ContextualChatPanel` uses `context.chatSystemPrompt` directly.

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

## - [x] Phase 5: Remove XML structured output infrastructure

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Deleted the four XML/structured-output source files (`AIResponseDescriptor`, `AIResponseHandling`, `AIResponseRouter`, `StructuredOutputParser`) and their corresponding tests. Removed `responseDescriptors` from `AIClientOptions` and `SendChatMessageUseCase.Options`, stripped `responseHandler` and all related XML-parsing logic from `ChatModel` and `ChatModelConfiguration`, and simplified the message-finalization path to use `existing.contentBlocks` directly (no stripping step needed).

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

## - [x] Phase 6: Validation

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Added `AppIPCSDKTests` as a new SDK-layer test target covering Codable encoding/decoding of IPC types and the `appNotRunning` error path. Added `MCPCommandTests` in `AIDevToolsKitCLITests` covering command configuration and tool handler behavior (graceful app-not-running handling, list_plans shape). Made `handleCallTool` internal (removed `private`) to enable `@testable import` testing. Fixed pre-existing compilation errors in `ClaudeChainSDKTests`, `ClaudeChainFeatureTests`, and `PipelineSDKTests` (missing required parameters added to initializers) so the full test suite compiles. Build passes cleanly; 679 tests run, 3 pre-existing failures from missing local fixture files unrelated to this phase.

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
## - [x] Find new features architected as afterthoughts and refactor them to integrate cleanly with the existing system

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Three scattered app-level paths (`app.sock`, `deeplink.txt`, `mcp-config.json`) were each hardcoded independently in 2–3 files — a classic afterthought pattern. Fixed by (1) adding `DataPathsService.deepLinkFileURL` and `DataPathsService.mcpConfigFileURL` as static constants so both CLI and Mac app targets share a single source of truth, and (2) promoting `AppIPCClient.socketFilePath` to `public static` so `AppIPCServer` derives the path from the SDK rather than recomputing it. Also moved MCP config file writing out of the SwiftUI `ContextualChatPanel` View (wrong layer for I/O) into `CompositionRoot.create()` at app startup — the View now references the well-known path constant instead of writing the file itself.

## - [x] Identify the architectural layer for every new or modified file; read the reference doc for that layer before reviewing anything else

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Read `swift-app-architecture:swift-architecture` before cataloguing files. All new/modified files map correctly to their declared layers:

| File | Layer | Correct? |
|------|-------|----------|
| `SDKs/AppIPCSDK/AppIPCClient.swift` | SDKs | ✓ Stateless `Sendable` struct, single operation |
| `SDKs/AppIPCSDK/IPCRequest.swift` | SDKs | ✓ Codable value type, no app logic |
| `SDKs/AppIPCSDK/IPCUIState.swift` | SDKs | ✓ Codable value type, no app logic |
| `SDKs/AIOutputSDK/AIClient.swift` | SDKs | ✓ SDK-level options struct |
| `SDKs/ClaudeCLISDK/` | SDKs | ✓ Single-operation CLI wrapper |
| `Services/DataPathsService/DataPathsService.swift` | Services | ✓ Shared path constants, no orchestration |
| `Apps/AIDevToolsKitCLI/MCPCommand.swift` | Apps (CLI) | ✓ Entry point / ArgumentParser command |
| `Apps/AIDevToolsKitCLI/EntryPoint.swift` | Apps (CLI) | ✓ Entry point registration |
| `Apps/AIDevToolsKitMac/IPC/AppIPCServer.swift` | Apps (Mac) | ✓ `@MainActor` server, platform I/O |
| `Apps/AIDevToolsKitMac/Models/PlansChatContext.swift` | Apps (Mac) | ✓ App-layer model |
| `Apps/AIDevToolsKitMac/Views/Chat/ContextualChatPanel.swift` | Apps (Mac) | ✓ SwiftUI view |
| `Apps/AIDevToolsKitMac/Views/Chat/ViewChatContext.swift` | Apps (Mac) | ✓ App-layer protocol |
| `AIDevTools/AIDevToolsApp.swift` | Apps (Mac) | ✓ `@main` entry point |
## - [x] Find code placed in the wrong layer entirely and move it to the correct one

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: `ChatSettings` (`@Observable final class`) was in `Features/ChatFeature` — wrong layer, since `@Observable` is an Apps-layer concern. All callers were in `AIDevToolsKitMac`. Moved to `Apps/AIDevToolsKitMac/Models/ChatSettings.swift` and removed the now-stale `import ChatFeature` from five files that had only imported it for `ChatSettings` (`MarkdownPlannerModel`, `ClaudeChainModel`, `GeneralSettingsView`, `ChatSettingsView`, `ContextualChatPanel`). Test moved from `ChatFeatureTests` to `AIDevToolsKitMacTests`.
## - [x] Find upward dependencies (lower layers importing higher layers) and remove them

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Found two SDK targets importing Service-layer modules: `EvalSDK` importing `EvalService` (`OutputService`, `RubricEvaluator`), and `ClaudeChainSDK` importing `ClaudeChainService` (`ProjectRepository`, `ScriptRunner`, `FileSystemOperations`, `GitHubOperations`). Fix was to move each violating file up to the Service layer it depended on. `ClaudeChainService` now depends on `ClaudeChainSDK` (correct downward direction) and `CLISDK`. `GitHubOperationsProtocol` stays in `ClaudeChainSDK` with the unused import removed. Corresponding tests moved from `EvalSDKTests`/`ClaudeChainSDKTests` to `EvalServiceTests`/`ClaudeChainServiceTests`.
## - [x] Find `@Observable` or `@MainActor` outside the Apps layer and move it up

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Searched all layers for `@Observable` and `@MainActor` usage. `@Observable` is correctly confined to `Apps/AIDevToolsKitMac/Models/` and `Apps/AIDevToolsKitMac/PRRadar/Models/` — no violations. `@MainActor` appears on methods in `ArchitecturePlannerFeature` use cases (12 files) and `ArchitecturePlannerService/ArchitecturePlannerStore.createContext()` — but this is a SwiftData constraint: `ModelContext` is declared `@MainActor final class`, so any code that creates or accesses a `ModelContext` must be `@MainActor`. This cascades from `ArchitecturePlannerStore.createContext()` through all ArchitecturePlanner use cases. These are SwiftData-mandated, not architectural mistakes. The proper fix (migrating to `@ModelActor` background persistence) would be a significant refactor and is tracked as future work. No changes required; build confirmed clean.
## - [x] Find multi-step orchestration that belongs in a use case and extract it

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Found `MCPCommand.handleGetPlanDetails()` in the Apps layer doing 3 sequential operations: load all plans via `LoadPlansUseCase`, find a plan by name, read its file content. Extracted into `GetPlanDetailsUseCase` in `MarkdownPlannerFeature` — the correct Feature layer — with a typed error enum (`planNotFound`, `contentUnreadable`). `MCPCommand.handleGetPlanDetails()` now delegates to the use case and maps the thrown errors to MCP tool results.
## - [x] Find feature-to-feature imports and replace with a shared Service or SDK abstraction

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Audited all 9 Feature modules (`ArchitecturePlannerFeature`, `ChatFeature`, `ClaudeChainFeature`, `CredentialFeature`, `EvalFeature`, `MarkdownPlannerFeature`, `PipelineFeature`, `PRReviewFeature`, `SkillBrowserFeature`). No feature imports another feature — every Feature target's dependencies in `Package.swift` point only to Services, SDKs, and external packages. Architecture is fully compliant; no changes required.
## - [x] Find SDK methods that accept or return app-specific or feature-specific types and replace them with generic parameters

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Audited all 18 SDK modules (90 Swift files) for public methods accepting or returning Feature/App layer types. All SDK public APIs exclusively use Swift standard library types, SDK-defined Codable/Sendable types, and primitives — zero imports of Feature or Service modules found. No changes required; architecture is fully compliant.
## - [x] Find SDK methods that orchestrate multiple operations and split them into single-operation methods

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Found two violations. (1) `GitClient.diffChangedFiles` and `diffDeletedFiles` each called `ensureRefAvailable` for both refs internally — bundling a conditional fetch (I/O) with a git diff (CLI) in a single SDK method. Removed those calls so each method is a pure single-operation diff; moved the `ensureRefAvailable` calls up to `AutoStartService` (Feature layer), which now ensures refs once before both diffs. (2) `GitOperationsService.diffNoIndex` mixed temp file I/O, git CLI invocation, and path-label string rewriting. Extracted `rewriteDiffLabels(diff:oldPath:oldLabel:newPath:newLabel:) -> String` as a public static method so the string transformation is independently callable and testable; `diffNoIndex` now delegates to it.
## - [x] Find SDK types that hold mutable state and refactor to stateless structs

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Found six violations. (1) `AnthropicAPIClient` actor had a mutable `apiKey` with a dead `updateAPIKey()` method — changed to `let` and removed the method. (2) `AnthropicProvider` actor held a `private var conversations` in-memory cache — removed it; every `run()` call now loads from `AnthropicSessionStorage` directly, making the actor stateless. (3) `ProviderResult` had nine `public var` properties — changed to `let`; refactored `ClaudeOutputParser.buildResult()` and `OutputService.writeEvalArtifacts()` to construct the result in one shot rather than mutating after the fact. (4) `ToolCallSummary` had four `public var` counter properties — changed to `let`; refactored `ClaudeOutputParser` and `CodexOutputParser` to accumulate with local `Int` variables and construct the summary at the end. (5) `ProcessDiagnostics` had six `public var` enrichment fields set after construction in `findResultEvent()` — changed to `let`, added an internal memberwise init and an `enriched(...)` method that returns a new copy with the enrichment fields filled in. (6) `Pipeline` had `var steps` and `var metadata` — changed to `let` (no callers mutated these after construction). Also fixed `CodexProvider+EvalCapable` which post-mutated a `ProviderResult` from `buildResult`.
## - [x] Find error swallowing across all layers and replace with proper propagation

**Skills used**: none
**Principles applied**: Fixed `try?` in `AIRunSession` (5 sites across `run`, `runStructured`, `startRun`, `startStructuredRun`, and the deprecated closure-based `run`) and in `AnthropicProvider.run` (session persistence). Intentional partial-failure patterns were left in place: `RuleLoaderService` (git URL decoration is non-fatal to rule loading), `CommentService` (batch comment operations count failures and return them to the caller), `FocusGeneratorService`/`AnalysisService` (transcript writes are non-fatal to the analysis result).
## - [x] Verify use case types are structs conforming to `UseCase` or `StreamingUseCase`, not classes or actors

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Created a new `UseCaseSDK` module with `UseCase` and `StreamingUseCase` marker protocols (both refining `Sendable`). Added `UseCaseSDK` as a dependency to all 9 Feature targets plus `DataPathsService` (which hosts 2 service-layer use cases). Added `UseCase` conformance to 58 regular use cases and `StreamingUseCase` conformance to 10 streaming ones (those returning `AsyncThrowingStream` or `AsyncStream`). All 68 `*UseCase` types were already structs — zero class or actor violations found. Build passes cleanly.
## - [x] Verify type names follow the `<Name><Layer>` convention and rename any that don't

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Audited all 42 production targets. Found one violation: `PRRadarModels` in the Services layer lacked the required `Service` suffix. Renamed to `PRRadarModelsService` (directory, Package.swift library/target/test target, and all ~80 `import`/`@testable import` statements across Features, Services, and Apps layers). One module-qualifier call `PRRadarModels.displayName(...)` inside the module itself was also updated to `PRRadarModelsService.displayName(...)`.
## - [x] Verify both a Mac app model and a CLI command consume each new use case

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: The only new use case introduced in this document's phases is `GetPlanDetailsUseCase` (extracted from `MCPCommand` during the "Find multi-step orchestration" phase). It was already consumed by `MCPCommand.handleGetPlanDetails()` (CLI). Added `getPlanDetails(planName:repository:)` to `MarkdownPlannerModel` (Mac app model layer) delegating to the use case. Updated `MarkdownPlannerDetailView.loadPlan()` to `async` and routed it through the model method, making `handleExecutionComplete()` `async` as well to preserve the load-then-merge phase ordering.
