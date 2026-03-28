## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer Swift app architecture (Apps, Features, Services, SDKs) |
| `ai-dev-tools-debug` | File paths, CLI commands, and artifact structure for AIDevTools |

## Background

`ChatManager` is an `@Observable` `@MainActor` class living in the Services layer (`ChatManagerService`). This violates two architecture principles:

1. **@Observable at the App Layer Only** — `@Observable` models belong in Apps, not Services
2. **Use Cases Orchestrate** — `ChatManager` does multi-step orchestration (build prompt with images, call `client.run()`, stream chunks into messages, handle errors, process message queue, manage sessions) directly in an observable class. This logic belongs in a Feature-layer use case.

Additionally, the project already has two provider-specific chat features (`AnthropicChatFeature` and `ClaudeCodeChatFeature`) with use cases that `ChatManager` duplicates rather than consumes. The CLI uses these feature use cases but branches on provider type (`if client is AnthropicAIClient`), violating the provider commoditization pattern.

### Current state

```
ChatManagerService (Services)
  └── ChatManager (@Observable) — duplicates use case logic, handles all providers
  └── ChatMessage, ChatSettings — shared types

AnthropicChatFeature (Features)
  └── SendChatMessageUseCase — Anthropic-specific (no workingDir, no images)

ClaudeCodeChatFeature (Features)
  └── SendClaudeCodeMessageUseCase — CLI-specific (workingDir, dangerouslySkipPermissions)
  └── ListClaudeCodeSessionsUseCase — Claude-specific name, generic implementation
  └── ScanSkillsUseCase — unrelated to chat, but lives here

CLI ChatCommand — branches on AnthropicAIClient vs CLI providers
Mac WorkspaceView — uses ChatManager directly
```

### Target state

```
ChatFeature (Features)
  └── SendChatMessageUseCase — unified, works with any AIClient
  └── ListSessionsUseCase — provider-agnostic
  └── ScanSkillsUseCase — moved here from ClaudeCodeChatFeature

ChatModel (Apps/Mac)
  └── @Observable @MainActor — owns messages, isProcessing, messageQueue
  └── Consumes SendChatMessageUseCase for orchestration
  └── Calls SessionListable directly for trivial single-call session ops

CLI ChatCommand — uses unified SendChatMessageUseCase, no provider branching

ChatManagerService — deleted
AnthropicChatFeature — deleted
ClaudeCodeChatFeature — deleted
```

### Type placement

| Type | Current Location | Target Location | Reason |
|------|-----------------|----------------|--------|
| `ChatMessage`, `ContentLine` | ChatManagerService | ChatFeature/services | Feature-specific shared types |
| `ChatSettings` | ChatManagerService | ChatFeature/services | Chat configuration, used by feature and model |
| `QueuedMessage` | ChatManagerService | Apps/Mac (with ChatModel) | Only used by the model for UI queuing |
| `ChatManager` | ChatManagerService | **deleted** | Replaced by ChatModel + use case |

## Phases

## - [x] Phase 1: Create unified ChatFeature target

**Skills to read**: `swift-architecture`

Create a single `ChatFeature` target that replaces both `AnthropicChatFeature` and `ClaudeCodeChatFeature`.

### Unified SendChatMessageUseCase

Merge the two provider-specific use cases. The unified version accepts all options and works with any `AIClient`:

```swift
public struct SendChatMessageUseCase: Sendable {
    public struct Options: Sendable {
        public let message: String
        public let workingDirectory: String?
        public let sessionId: String?
        public let images: [ImageAttachment]
        public let systemPrompt: String?
    }

    public struct Result: Sendable {
        public let fullText: String
        public let sessionId: String?
        public let exitCode: Int32
    }

    public enum Progress: Sendable {
        case textDelta(String)
        case completed(fullText: String)
    }

    private let client: any AIClient

    public func run(
        _ options: Options,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> Result
}
```

Key decisions:
- Always set `dangerouslySkipPermissions: true` (matches `ChatManager` behavior)
- Include `workingDirectory` as optional (Anthropic API doesn't need it, CLI providers do)
- Include `images` (move the base64→temp-file logic from `ChatManager` into the use case — this is orchestration)
- Return `exitCode` in result so the caller can decide how to handle errors (model formats error messages, CLI prints them)
- Do NOT throw on non-zero exit codes — return the result with the exit code. The caller decides presentation. This avoids the current inconsistency where `ClaudeCodeChatError` exists but `ChatManager` handles exit codes without it.

### Rename ListClaudeCodeSessionsUseCase → ListSessionsUseCase

Same implementation, provider-agnostic name.

### Move ScanSkillsUseCase

Move from `ClaudeCodeChatFeature` to `ChatFeature`. No code changes needed — it's already provider-agnostic.

### Move shared types

Move `ChatMessage.swift` (includes `ContentLine`) and `ChatSettings.swift` from `ChatManagerService` into `ChatFeature/services/`.

Remove `@Observable` from `ChatSettings` — it's configuration data. The App-layer model can expose these properties observably if views need to bind to them. Alternatively, keep `@Observable` on `ChatSettings` since it's a lightweight config wrapper and the architecture principle is about models, not small config objects. Decide during implementation based on whether views bind directly to `ChatSettings`.

### Package.swift

- Add `ChatFeature` target depending on `AIOutputSDK` and `SkillScannerSDK`
- Remove `AnthropicChatFeature` and `ClaudeCodeChatFeature` targets
- Remove `ChatManagerService` library product
- Update `AIDevToolsKitCLI` and `AIDevToolsKitMac` dependencies

### Files to create

- `Features/ChatFeature/usecases/SendChatMessageUseCase.swift`
- `Features/ChatFeature/usecases/ListSessionsUseCase.swift`
- `Features/ChatFeature/usecases/ScanSkillsUseCase.swift` (moved)
- `Features/ChatFeature/services/ChatMessage.swift` (moved)
- `Features/ChatFeature/services/ChatSettings.swift` (moved)

### Files to delete

- `Features/AnthropicChatFeature/` (entire directory)
- `Features/ClaudeCodeChatFeature/` (entire directory)

## - [x] Phase 2: Create ChatModel in Apps layer (Mac)

**Skills to read**: `swift-architecture`

Create `ChatModel` as an `@Observable` `@MainActor` class in the Mac app. It replaces `ChatManager` and consumes `SendChatMessageUseCase`.

### ChatModel responsibilities

The model owns all UI state and state transitions:

```swift
@Observable
@MainActor
final class ChatModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var isProcessing: Bool = false
    private(set) var isLoadingHistory: Bool = false
    private(set) var messageQueue: [QueuedMessage] = []
    let providerDisplayName: String
    let settings: ChatSettings
    private(set) var workingDirectory: String

    // Identity / capabilities
    var providerName: String
    var currentSessionId: String?
    var supportsSessionHistory: Bool

    private let sendMessageUseCase: SendChatMessageUseCase
    private let client: any AIClient  // for session ops (trivial single-call)
}
```

### What the model does

1. **Translates user actions into use case calls** — `sendMessage()` builds use case `Options`, calls `sendMessageUseCase.run()`, consumes `Progress` callbacks to update the placeholder assistant message
2. **Owns state transitions** — progress callbacks map to message content updates; completion maps to `isComplete = true`; errors map to error message content
3. **Manages message queue** — if `isProcessing`, append to queue; after completion, process next queued message
4. **Session operations** — calls `client as? SessionListable` directly for `listSessions()` and `resumeSession()` (trivial single-call operations, acceptable per architecture)
5. **Working directory changes** — resets state, optionally auto-resumes last session

### QueuedMessage

Move `QueuedMessage` struct into this file — it's only used by the model.

### Files to create

- `Apps/AIDevToolsKitMac/Models/ChatModel.swift`

## - [x] Phase 3: Update Mac views to use ChatModel

**Skills to read**: `swift-architecture`

Replace all `ChatManager` references in Mac views with `ChatModel`.

### Views to update

All of these currently use `@Environment(ChatManager.self)`:

- `ChatPanelView.swift` → `@Environment(ChatModel.self)`
- `ChatSettingsView.swift` → `@Environment(ChatModel.self)`
- `ChatSessionPickerView.swift` → `@Environment(ChatModel.self)`
- `ChatSessionDetailView.swift` → `@Environment(ChatModel.self)`
- `ChatQueueViewerSheet.swift` → `@Environment(ChatModel.self)`

### WorkspaceView

Update `rebuildChatManager()` → `rebuildChatModel()`:
- Create `SendChatMessageUseCase(client: client)`
- Create `ChatModel(sendMessageUseCase:client:workingDirectory:settings:)`
- Change `@State private var chatManager: ChatManager?` → `@State private var chatModel: ChatModel?`
- Update environment injection from `.environment(chatManager)` to `.environment(chatModel)`
- Remove `import ChatManagerService`

### Files to modify

- `WorkspaceView.swift`
- `ChatPanelView.swift`
- `ChatSettingsView.swift`
- `ChatSessionPickerView.swift`
- `ChatSessionDetailView.swift`
- `ChatQueueViewerSheet.swift`

## - [x] Phase 4: Update CLI ChatCommand to use unified use case

**Skills to read**: `swift-architecture`

Remove the provider-type branching in `ChatCommand`. Currently it branches:
```swift
if client is AnthropicAIClient {
    try await runAnthropicChat(client: client)
} else {
    try await runCLIChat(client: client)
}
```

Replace with a single code path using the unified `SendChatMessageUseCase`:

```swift
func run() async throws {
    let registry = makeProviderRegistry()
    guard let client = registry.client(named: provider) else { ... }
    let useCase = SendChatMessageUseCase(client: client)

    if let message {
        try await sendMessage(message, useCase: useCase, client: client)
    } else {
        try await runInteractive(useCase: useCase, client: client)
    }
}
```

The session resume logic is already identical across both branches — it checks `SessionListable` and loads the most recent session. Unify into one implementation.

### Files to modify

- `ChatCommand.swift` — remove `runAnthropicChat`, `runCLIChat`, `sendAnthropicMessage`, `sendCLIMessage`, `runAnthropicInteractive`, `runCLIInteractive`; replace with unified `sendMessage` and `runInteractive`
- Remove `import AnthropicChatFeature`, `import ClaudeCodeChatFeature`, `import AnthropicSDK`, `import ClaudeCLISDK`; add `import ChatFeature`

## - [x] Phase 5: Remove old targets and clean up Package.swift

**Skills to read**: `swift-architecture`

### Delete old source directories

- `Sources/Services/ChatManagerService/` (entire directory)
- `Sources/Features/AnthropicChatFeature/` (entire directory)
- `Sources/Features/ClaudeCodeChatFeature/` (entire directory)
- `Tests/Services/ChatManagerServiceTests/` (entire directory)
- `Tests/Features/ClaudeCodeChatFeatureTests/` (entire directory)

### Package.swift changes

Remove targets:
- `ChatManagerService` (target + library product)
- `AnthropicChatFeature` (target + library product)
- `ClaudeCodeChatFeature` (target + library product)
- `ChatManagerServiceTests` (test target)
- `ClaudeCodeChatFeatureTests` (test target)

Add target:
- `ChatFeature` depending on `AIOutputSDK`, `SkillScannerSDK`
- `ChatFeatureTests` depending on `ChatFeature`, `SkillScannerSDK`

Update dependencies:
- `AIDevToolsKitCLI`: replace `AnthropicChatFeature` + `ClaudeCodeChatFeature` with `ChatFeature`
- `AIDevToolsKitMac`: replace `ChatManagerService` with `ChatFeature`

### Migrate tests

- Move `ScanSkillsUseCaseTests` from `ClaudeCodeChatFeatureTests` to `ChatFeatureTests` (update import)
- Move `ChatMessageTests` and `ChatSettingsTests` from `ChatManagerServiceTests` to `ChatFeatureTests` (update import)

## - [x] Phase 6: Validation

**Skills to read**: `ai-dev-tools-debug`

### Automated

- Build both CLI and Mac app targets with no compile errors
- Run full test suite — all existing tests pass (migrated to `ChatFeatureTests`)
- Grep checks:
  - `grep -r "ChatManager" --include="*.swift" Sources/` — expect zero matches (only `ChatModel` remains)
  - `grep -r "import ChatManagerService" --include="*.swift"` — expect zero
  - `grep -r "import AnthropicChatFeature\|import ClaudeCodeChatFeature" --include="*.swift"` — expect zero
  - `grep -r "AnthropicAIClient" --include="*.swift" Sources/Apps/AIDevToolsKitCLI/ChatCommand.swift` — expect zero (no provider branching)

### Manual

- Mac app: chat works with each provider (Claude, Codex, Anthropic API)
- Mac app: session picker appears for providers that support it
- Mac app: session resume works
- Mac app: message queuing works (send while processing)
- Mac app: working directory change resets chat
- Mac app: settings panel works
- CLI: `ai-dev-tools-kit chat --provider claude "hello"` — works
- CLI: `ai-dev-tools-kit chat --provider codex "hello"` — works
- CLI: `ai-dev-tools-kit chat --provider anthropic-api "hello"` — works
- CLI: `ai-dev-tools-kit chat --resume` — resumes last session
