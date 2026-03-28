## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer Swift app architecture (Apps, Features, Services, SDKs) |

## Background

The provider commoditization spec (2026-03-27-b) made providers interchangeable at the SDK and CLI layers. But the Mac app's chat panel still has two entirely separate code paths — `ChatViewModel` + `ChatView` for Anthropic API, and `ClaudeCodeChatManager` + `ClaudeCodeChatView` for CLI providers. `WorkspaceView` branches on `chatProviderName == "anthropic-api"` to pick between them.

This is unnecessary. The `AIClient` protocol already abstracts "send prompt, get streaming response" with `sessionId` for continuity. Both chat managers do the same thing — call `client.run()`, stream via `onOutput`, track `sessionId`. The duplication exists because the Anthropic path was built before the protocol was unified.

Worse, the Anthropic path's SwiftData persistence layer is **broken** — `loadConversation()` sets `sessionId = nil`, so "resuming" a conversation loads the messages for display but loses the actual API context. Meanwhile `AnthropicAIClient` already maintains real session history in-memory keyed by `sessionId`.

### What's wrong today

| Location | Problem |
|----------|---------|
| `CompositionRoot.swift` | Registry only contains CLI clients; Anthropic API excluded |
| `WorkspaceView` | Two separate state vars (`claudeCodeChatManager` + `chatViewModel`), branches on provider name |
| `WorkspaceView` | Imports `AnthropicSDK`, `ClaudeCLISDK` — concrete SDK knowledge in a view |
| `ChatViewModel` | Duplicate of `ClaudeCodeChatManager` but simpler; broken session resume |
| `ChatView` | Separate view doing the same thing as `ClaudeCodeChatView` |
| Session history | `ClaudeCodeChatManager` reads Claude's JSONL files; `ChatViewModel` uses SwiftData; should be provider-managed |

### Design principles for this plan

1. **One chat manager** — a single `ChatManager` that works with any `AIClient` via the protocol
2. **Providers own persistence** — session history is the provider's responsibility, not the chat UI's. Claude CLI stores JSONL files. Anthropic API maintains in-memory history (SwiftData persistence comes later as an enhancement to `AnthropicAIClient` itself). Codex will get its own mechanism later.
3. **Session listing is a capability** — not all providers support listing/resuming prior sessions. Claude CLI does (JSONL files). Anthropic API doesn't yet. This is exposed as an optional capability, not a provider-name check.

### Target state

```
AIClient protocol (SDK layer)
  └── run() with sessionId for continuity — provider manages its own history

ChatManager (Service layer)
  └── Single implementation for all providers
  └── Calls client.run(), tracks sessionId, manages UI message list
  └── No persistence — that's the provider's job

ChatView (Feature/App layer)
  └── Single view, works with ChatManager
  └── Session picker shown when provider supports it (capability check)
  └── Settings shown when relevant
```

## Phases

## - [x] Phase 1: Make ProviderRegistry mutable and register Anthropic API

**Skills used**: `swift-architecture`
**Principles applied**: Kept `@Observable` at Apps layer only via `ProviderModel`; `ProviderRegistry` stays immutable Sendable struct in Services; model rebuilds registry on settings change; views observe the model, not the registry directly

**Skills to read**: `swift-architecture`

### Make ProviderRegistry a class

`ProviderRegistry` is currently a struct created once at launch. The Mac app needs to add/remove providers at runtime (e.g., when the user enters an API key in Settings). Convert it to an `@Observable` class:

```swift
@Observable
@MainActor
public final class ProviderRegistry {
    public private(set) var providers: [any AIClient]

    public init(providers: [any AIClient]) {
        self.providers = providers
    }

    public func register(_ client: any AIClient) {
        guard !providers.contains(where: { $0.name == client.name }) else { return }
        providers.append(client)
    }

    public func unregister(named name: String) {
        providers.removeAll { $0.name == name }
    }

    // existing helpers unchanged
    public var providerNames: [String] { providers.map(\.name) }
    public func client(named name: String) -> (any AIClient)? {
        providers.first { $0.name == name }
    }
}
```

### Register Anthropic API conditionally

`CompositionRoot` conditionally registers `AnthropicAIClient` if a key exists at launch:

```swift
if let key = UserDefaults.standard.string(forKey: "anthropicAPIKey"), !key.isEmpty {
    let anthropic = AnthropicAIClient(apiClient: AnthropicAPIClient(apiKey: key))
    providerRegistry.register(anthropic)
}
```

### Refresh from Settings

When the user adds or changes the API key in `GeneralSettingsView`, call `register`/`unregister` on the registry. Since `ProviderRegistry` is `@Observable`, the picker in `WorkspaceView` updates automatically:

```swift
// In GeneralSettingsView, on API key change:
if !newKey.isEmpty {
    providerRegistry.register(AnthropicAIClient(apiClient: AnthropicAPIClient(apiKey: newKey)))
} else {
    providerRegistry.unregister(named: "anthropic-api")
}
```

### Remove manual provider list from WorkspaceView

`WorkspaceView` currently builds `chatProviders` by mapping the registry and manually appending `"anthropic-api"`. Replace with just `providerRegistry.providers` — the registry now has everything.

### CLI impact

The CLI uses `ProviderRegistry` as a value passed into commands. Since CLI commands are short-lived, mutability doesn't matter — they create the registry, use it, and exit. The struct-to-class change is compatible; the CLI factory functions just need minor signature adjustments if any.

### Files to modify

- `ProviderRegistryService/ProviderRegistry.swift` — convert to `@Observable` class, add `register`/`unregister`
- `CompositionRoot.swift` — add `AnthropicSDK` import, conditionally register `AnthropicAIClient`
- `GeneralSettingsView.swift` — register/unregister on API key change
- `WorkspaceView.swift` — remove `chatProviders` computed property, use `providerRegistry.providers` for picker; remove manual `"anthropic-api"` append
- `CLIRegistryFactory.swift` — minor adjustments if needed for class vs struct

## - [x] Phase 2: Unify ChatManager

**Skills used**: `swift-architecture`
**Principles applied**: Created `ChatManagerService` at Services layer with `AIOutputSDK` dependency only; combined streaming, queuing, and image handling from both managers into a single provider-agnostic `ChatManager`

**Skills to read**: `swift-architecture`

Replace both `ClaudeCodeChatManager` and `ChatViewModel` with a single `ChatManager` that works with any `AIClient`.

### Core design

```swift
@Observable
@MainActor
public final class ChatManager {
    public private(set) var messages: [ChatMessage]
    public private(set) var isProcessing: Bool
    public private(set) var streamingContent: String
    public let providerDisplayName: String

    private let client: any AIClient
    private var sessionId: String?

    public init(client: any AIClient, workingDirectory: String?)

    public func sendMessage(_ content: String, images: [ImageAttachment]) async
    public func startNewConversation()
    public func cancelCurrentRequest()
}
```

`ChatMessage` is the unified display model:

```swift
public struct ChatMessage: Identifiable, Sendable {
    public let id: UUID
    public let role: Role
    public let content: String
    public let timestamp: Date
    public let isComplete: Bool

    public enum Role: Sendable { case user, assistant }
}
```

The `sendMessage` flow:
1. Append user message to `messages`
2. Append placeholder assistant message (empty, `isComplete: false`)
3. Call `client.run(prompt:options:onOutput:)` with current `sessionId`
4. `onOutput` callback updates the placeholder message content (streaming)
5. On completion, mark message `isComplete: true`, store returned `sessionId`

This is exactly what both existing managers do. The unified version drops:
- SwiftData persistence (was broken anyway; Anthropic API manages its own in-memory history)
- JSONL file reading for session resume (stays in Phase 3 as a capability)
- Message queuing (move to this manager from `ClaudeCodeChatManager` — useful for all providers)

### Where to put it

`ChatManager` and `ChatMessage` go in `ClaudeCodeChatService` (rename to `ChatService` — it's no longer Claude-specific). Or create a new `ChatManagerService` target. The existing `ChatService` target may conflict — check what's already there.

### Files to create/modify

- New or renamed service with `ChatManager.swift` and `ChatMessage.swift`
- `Package.swift` — update target if renamed

## - [x] Phase 3: Add session listing as a capability on AIClient

**Skills used**: `swift-architecture`
**Principles applied**: Added `SessionListable` protocol and `ChatSession`/`ChatSessionMessage` types to `AIOutputSDK`; `ClaudeCLIClient` conforms with JSONL parsing moved from `ClaudeCodeChatManager`; `ChatManager` uses `client is SessionListable` capability check

**Skills to read**: `swift-architecture`

Session listing (loading prior sessions from disk) is currently baked into `ClaudeCodeChatManager`. It reads Claude's JSONL files from `~/.claude/projects/`. This is Claude-specific knowledge that belongs closer to the provider.

Add an optional protocol extension:

```swift
public protocol SessionListable {
    func listSessions(workingDirectory: String) async -> [ChatSession]
    func loadSessionMessages(sessionId: String, workingDirectory: String) async -> [ChatMessage]
}
```

`ClaudeCLIClient` conforms — it already knows how to read `~/.claude/projects/`. Move the JSONL parsing logic from `ClaudeCodeChatManager` into `ClaudeCLISDK`.

`AnthropicAIClient` and `CodexCLIClient` don't conform yet. When they get persistence later, they can adopt it.

`ChatManager` checks `client is SessionListable` to decide whether to show session picker UI. This replaces the `supportsSessionHistory` property we added earlier (which checked `client.name == "claude"`).

```swift
public var supportsSessionHistory: Bool {
    client is SessionListable
}

public func listSessions() async -> [ChatSession] {
    guard let listable = client as? SessionListable else { return [] }
    return await listable.listSessions(workingDirectory: workingDirectory)
}
```

### ChatSession

Generalize `ClaudeSession` into a provider-agnostic type:

```swift
public struct ChatSession: Identifiable, Sendable {
    public let id: String
    public let summary: String
    public let lastModified: Date
}
```

### Files to modify

- `AIOutputSDK` or `ChatService` — add `SessionListable` protocol, `ChatSession` type
- `ClaudeCLISDK/ClaudeCLIClient.swift` — conform to `SessionListable`, move JSONL parsing here
- `ChatManager` — use `SessionListable` for session list/resume
- Remove `ClaudeCodeChatSession.swift` types that are now generalized

## - [x] Phase 4: Unify chat views

**Skills used**: `swift-architecture`
**Principles applied**: Single `ChatPanelView` works with any provider via `ChatManager`; capability-driven UI (session picker only shown when `supportsSessionHistory`); merged rich input area from `ClaudeCodeChatView` as the unified input

**Skills to read**: `swift-architecture`

Replace `ChatView` (Anthropic) and `ClaudeCodeChatView` with a single `ChatPanelView` that works with `ChatManager`.

### Message display

Use `ChatMessage` for all providers. The existing `ClaudeCodeChatMessageRow` already handles:
- Role-based icons and labels
- Thinking block parsing (🧠)
- Tool use display (🔧)
- Streaming indicator

These aren't Claude-specific — any provider could return thinking blocks. Keep this rich rendering as the unified message row, using `chatManager.providerDisplayName` for the label (already done in our earlier fix).

### Capabilities drive UI

```swift
// Session picker — only if provider supports it
if chatManager.supportsSessionHistory {
    // show session history button in toolbar
}

// Image paste — available for all providers (AIClient.run accepts any prompt text)
// Settings — keep, applicable to all CLI providers
```

### Input area

Merge the input areas. `ClaudeCodeChatView`'s input is richer (image paste, queue viewer, cancel button). Use that as the base. The streaming toggle from `ChatView` can be dropped — streaming is always on.

### Files to create

- `Views/Chat/ChatPanelView.swift` — unified view

### Files to delete

- `Views/AnthropicChat/ChatView.swift`
- `Views/AnthropicChat/MessageBubbleView.swift`
- `Models/ChatViewModel.swift`

### Files to modify

- `WorkspaceView.swift` — single `@State var chatManager: ChatManager?`, single `chatPanelView`, single rebuild method
- Remove imports of `AnthropicSDK`, `ClaudeCLISDK`, `AnthropicChatService`, `ClaudeCodeChatService` from `WorkspaceView`

## - [x] Phase 5: Clean up

**Skills used**: `swift-architecture`
**Principles applied**: Removed `ClaudeCodeChatService`, `AnthropicChatService` targets entirely; moved `ImageAttachment` to `AIOutputSDK` as shared type; deleted `ChatViewModel`, `ClaudeCodeChatManager`, `ConversationManager`, and all duplicate message types

Remove dead code:
- `ClaudeCodeChatManager` — replaced by unified `ChatManager`
- `ChatViewModel` — replaced by unified `ChatManager`
- `ChatMessageUI` — replaced by `ChatMessage`
- `ClaudeCodeChatMessage` — replaced by `ChatMessage`
- `ClaudeSession`, `SessionState`, `SessionDetails` — replaced by `ChatSession`
- `ConversationManager` and SwiftData models (`ChatConversation`, `ChatMessage` from `AnthropicChatService`) — persistence is provider-managed now
- `ClaudeCodeChatService` target (if fully emptied) or rename
- `AnthropicChatService` target (if fully emptied)
- Unused imports across the codebase

Update `Package.swift` to remove dead targets and add new ones.

## - [x] Phase 6: Validation

**Skills used**: `swift-architecture`
**Principles applied**: Build passes for both CLI and Mac app; all new tests pass; zero `ClaudeCodeChatManager`/`ChatViewModel` references remain; no concrete SDK imports in `WorkspaceView`

**Skills to read**: `swift-architecture`, `ai-dev-tools-debug`

### Automated

- Build both CLI and Mac app targets with no compile errors
- Run full test suite
- Grep `WorkspaceView.swift` for `"anthropic"`, `"claude"`, `"codex"` string literals — expect zero
- Grep `WorkspaceView.swift` imports for concrete SDK modules — expect zero
- Grep Features and Services for `ClaudeCodeChatManager`, `ChatViewModel` — expect zero (deleted)

### Manual

- Mac app: provider picker shows all registered providers dynamically
- Mac app: selecting Claude — chat works, session history button visible, can resume a prior session
- Mac app: selecting Codex — chat works, no session history button
- Mac app: selecting Anthropic API — chat works, no session history button (yet)
- Mac app: message bubbles show correct provider name for each provider
- Mac app: switching providers starts fresh (no history mixing)
- Mac app: image paste works for CLI providers
- CLI: `ai-dev-tools-kit chat --provider claude "hello"` — still works
- CLI: `ai-dev-tools-kit chat --provider codex "hello"` — still works
- CLI: `ai-dev-tools-kit chat --provider anthropic-api "hello"` — still works (reads from .env)

## - [x] Phase 7: Anthropic API session persistence

**Skills used**: `swift-architecture`
**Principles applied**: JSON file persistence in `~/.aidevtools/anthropic/sessions/` owned by `AnthropicAIClient`; actor-isolated `AnthropicSessionStorage` handles reads/writes; conforms to `SessionListable` so session picker appears automatically; lazy-loads persisted history on session resume

`AnthropicAIClient` currently holds conversation history in-memory (`conversations` dictionary keyed by `sessionId`). Sessions are lost on app restart. Add SwiftData persistence to `AnthropicAIClient` itself so it owns its storage.

### Design

Move the existing SwiftData models (`ChatConversation`, `ChatMessage`) from `AnthropicChatService` into `AnthropicSDK`. `AnthropicAIClient` writes to SwiftData on each `run()` call — after appending the user message and receiving the assistant response, persist both. On init, load existing sessions from SwiftData to populate the `conversations` dictionary.

Then conform `AnthropicAIClient` to `SessionListable`:
- `listSessions()` queries SwiftData for all `ChatConversation` records
- `loadSessionMessages()` loads the messages for a given conversation

Once this is in place, the session picker automatically appears for Anthropic API in the Mac app — no UI changes needed.

### Files to modify

- `AnthropicSDK/AnthropicAIClient.swift` — add SwiftData persistence, conform to `SessionListable`
- Move `ChatConversation.swift` and `ChatMessage.swift` from `AnthropicChatService` to `AnthropicSDK` (or keep in service if SDK shouldn't depend on SwiftData)
- `Package.swift` — update dependencies

## - [ ] Phase 8: Codex session history

**Skills to read**: `swift-architecture`

Investigate Codex CLI's session storage mechanism and conform `CodexCLIClient` to `SessionListable`.

### Research needed

- Where does Codex store session history? (equivalent of `~/.claude/projects/`)
- What format? (JSONL, JSON, SQLite?)
- Does Codex support `--resume` or session IDs?

Once understood, implement:
- `CodexCLIClient` conforms to `SessionListable`
- Parse Codex's session files into `ChatSession` / `ChatMessage`
- Session picker appears automatically for Codex

### Files to modify

- `CodexCLISDK/CodexCLIClient.swift` — conform to `SessionListable`

## - [ ] Phase 9: Validation (persistence)

**Skills to read**: `ai-dev-tools-debug`

### Anthropic API

- Send messages, quit app, relaunch — prior sessions appear in session picker
- Resume a session — conversation context is preserved (API knows prior messages)
- Create multiple sessions — all listed correctly

### Codex

- Send messages via Codex, session history loads from Codex's storage
- Resume a Codex session — conversation continues

### Regression

- Claude session resume still works
- Provider switching still starts fresh
- All CLI chat commands still work
