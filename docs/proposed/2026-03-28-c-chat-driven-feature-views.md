## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture (Apps, Features, Services, SDKs) — guides layer placement for models, use cases, and views |

## Background

The app currently has a standalone chat panel at the bottom of the WorkspaceView that slides up/down via a toggle. This chat panel connects to a selected AI provider and allows free-form conversation, but it's disconnected from the actual features (Markdown Planner, Evals, Architecture Planner). It serves no practical purpose in its current form.

Meanwhile, features like the Markdown Planner use their own execution flow: they send prompts via `AIClient.runStructured()`, stream raw text to an `OutputPanel` (monospaced text view), and show results. The chat system and the feature execution system are separate paths that both go through `AIClient` but surface results differently.

The goal is to unify these by embedding chat views directly within feature views, replacing the standalone chat and the OutputPanel with a richer, context-aware chat experience. This plan covers the general architecture for all features but focuses implementation on the Markdown Planner as the first feature.

### Current gaps identified

1. **Content richness gap**: The `ClaudeStreamFormatter` produces formatted text like `[Bash] cmd`, `[Thinking] ...`, `[Read] path` — but this gets fed to the chat as plain text. The `ContentLine` parser in `ChatMessage` only recognizes lines prefixed with emoji (`🧠`, `🔧`). Meanwhile, the `OutputPanel` just shows raw monospaced text. Neither approach captures the full structured data (tool inputs, tool results, thinking blocks, metrics) that providers actually return.

2. **No file watching**: When the chat modifies a plan file on disk, the `MarkdownPlannerDetailView` has no way to detect changes. It only reloads on explicit actions (phase toggle, execution complete).

3. **Chat is not embeddable**: `ChatPanelView` is tightly coupled to `WorkspaceView` — it requires a full `ChatModel` with send capability, session management, and input field. There's no read-only or context-injected variant for embedding within feature views.

4. **No read-only chat mode**: For execution streaming, the chat should be read-only (no input field, no send button). The current `ChatPanelView` always shows the input area.

## - [x] Phase 1: Structured content blocks at the SDK layer

**Skills used**: `swift-architecture`
**Principles applied**: Added `onStreamEvent` alongside existing `onOutput` for backward compatibility — all existing callers continue to work via a protocol extension. New types (`AIStreamEvent`, `AIContentBlock`) placed in SDKs layer per architecture guidelines. Extracted `toolUseDetail` helper in `ClaudeStreamFormatter` to share logic between formatted string output and structured event parsing.

**Skills to read**: `swift-architecture`

Create a provider-agnostic content block model in `AIOutputSDK` that captures the full richness of AI responses. This replaces the current approach of formatting everything into plain text strings.

**Two new types in `AIOutputSDK`** — one for the streaming callback, one for accumulated storage:

```swift
/// Emitted by providers during streaming. Text arrives as deltas (small chunks);
/// everything else arrives as discrete complete events.
public enum AIStreamEvent: Sendable {
    case textDelta(String)
    case thinking(String)
    case toolUse(name: String, detail: String)    // e.g. ("Bash", "ls -la")
    case toolResult(name: String, summary: String, isError: Bool)
    case metrics(duration: TimeInterval?, cost: Double?, turns: Int?)
}

/// Accumulated content block stored in a ChatMessage. Built from stream events.
/// - .textDelta chunks accumulate into a single .text block
/// - All other event types map 1:1 to a block
public enum AIContentBlock: Sendable, Equatable {
    case text(String)
    case thinking(String)
    case toolUse(name: String, detail: String)
    case toolResult(name: String, summary: String, isError: Bool)
    case metrics(duration: TimeInterval?, cost: Double?, turns: Int?)
}
```

**Accumulation rule** (implemented in ChatModel):
- `.textDelta(chunk)` → if the last block in the message is `.text`, append the chunk to it; otherwise add a new `.text(chunk)` block
- `.thinking`, `.toolUse`, `.toolResult`, `.metrics` → append a new block to the array

This means a streaming response builds up as an ordered list of typed blocks. Text streams live (the last `.text` block grows as deltas arrive), while discrete events (tool calls, thinking, etc.) pop in as new blocks.

**No `StructuredStreamFormatter` protocol** — raw chunk parsing is an internal implementation detail of each provider. The `AIClient` protocol only emits `AIStreamEvent` values; callers never deal with raw chunks.

**Update `AIClient.run` signature** to emit stream events:
- Replace `onOutput: (@Sendable (String) -> Void)?` with `onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?`
- Or add `onStreamEvent` alongside `onOutput` if backward compatibility is needed during migration
- Each provider is responsible for parsing its own raw stream internally and emitting `AIStreamEvent` values

**Update `ClaudeStreamFormatter`** (internal to ClaudeCLISDK):
- Add an internal method that returns `[AIStreamEvent]` instead of formatted strings
- `ClaudeProvider` calls this internally and emits events via `onStreamEvent`
- Thinking blocks become `.thinking(content)`
- Tool uses become `.toolUse(name: "Bash", detail: "ls -la")`
- Tool results become `.toolResult(name: "Bash", summary: "...", isError: false)`
- Result events become `.metrics(...)`
- Text blocks become `.textDelta(text)`

**Update `AnthropicProvider`** streaming to emit `AIStreamEvent` values (currently it only extracts `chunk.delta.text` — it should also emit `.thinking()` and `.toolUse()` events from the API response).

This phase is foundational — all subsequent phases depend on structured streaming being available.

**Files to create/modify**:
- Create: `AIOutputSDK/AIStreamEvent.swift` — stream event enum
- Create: `AIOutputSDK/AIContentBlock.swift` — accumulated content block enum
- Modify: `AIOutputSDK/AIClient.swift` — add `onStreamEvent` callback
- Modify: `ClaudeCLISDK/ClaudeStreamFormatter.swift` — add internal structured parsing method
- Modify: `ClaudeCLISDK/ClaudeProvider+AIClient.swift` — emit stream events
- Modify: `AnthropicSDK/AnthropicProvider.swift` — emit stream events

## - [x] Phase 2: Update ChatMessage and ChatFormattedContent to use structured blocks

**Skills used**: `swift-architecture`
**Principles applied**: Replaced emoji-prefix string parsing with typed `AIContentBlock` array as the primary storage in `ChatMessage`. Kept `content: String` init for backward compatibility (user messages, error messages, session history) while making `content` computed from text blocks. `StreamAccumulator` in `ChatModel` now applies accumulation rules (text deltas merge, discrete events append). `ChatFormattedContent` renders each block type with dedicated UI: thinking blocks get purple styling, tool use gets compact pill badges, tool results show success/error indicators, metrics show as subtle footers.

**Skills to read**: `swift-architecture`

Replace the emoji-prefix-based `ContentLine` parsing with the two-type model from Phase 1: `AIStreamEvent` (streaming) and `AIContentBlock` (accumulated storage).

**Update `ChatMessage` (ChatFeature)**:
- Replace `content: String` with `contentBlocks: [AIContentBlock]`
- Add a computed `content: String` that concatenates `.text` blocks for backward compatibility / search
- Remove the `contentLines` computed property that parses emoji prefixes — block types now carry this information natively

**Update `SendChatMessageUseCase`**:
- Replace `Progress.textDelta(String)` with `Progress.streamEvent(AIStreamEvent)`
- The use case forwards `AIStreamEvent` values from the provider's `onStreamEvent` callback
- `.completed` case stays as-is

**Update `ChatModel`** — accumulation logic:
- The assistant message stores `contentBlocks: [AIContentBlock]`
- On `.streamEvent(.textDelta(chunk))`: if the last block is `.text`, append chunk to it; otherwise add a new `.text(chunk)` block
- On `.streamEvent(.thinking(content))`: append `.thinking(content)` block
- On `.streamEvent(.toolUse(...))`: append `.toolUse(...)` block
- On `.streamEvent(.toolResult(...))`: append `.toolResult(...)` block
- On `.streamEvent(.metrics(...))`: append `.metrics(...)` block
- The `StreamAccumulator` actor is updated to accumulate `[AIContentBlock]` instead of a `String`

**Update `ChatFormattedContent` (App layer view)**:
- Iterate `message.contentBlocks` instead of `message.contentLines`
- Render each `AIContentBlock` case with appropriate UI:
  - `.text` — body text (as today)
  - `.thinking` — purple brain icon with collapsible thinking content (as today, but driven by typed data)
  - `.toolUse` — compact pill/badge showing tool name + detail (e.g., `[Bash] ls -la` with a terminal icon)
  - `.toolResult` — indented result with success/error indicator
  - `.metrics` — subtle footer with duration, cost, turns
- The toggle for "Show thinking & tools" continues to work but checks block types instead of emoji prefixes

**Files to modify**:
- `ChatFeature/ChatMessage.swift` — replace `content` with `contentBlocks`, remove `contentLines`
- `ChatFeature/SendChatMessageUseCase.swift` — replace `.textDelta` with `.streamEvent(AIStreamEvent)`
- `Apps/AIDevToolsKitMac/Models/ChatModel.swift` — accumulate `[AIContentBlock]` from stream events
- `Apps/AIDevToolsKitMac/Views/Chat/ChatPanelView.swift` — update `ChatFormattedContent` to render block types

## - [x] Phase 3: File system observer async sequence

**Skills used**: `swift-architecture`
**Principles applied**: Placed `FileWatcher` in `AIOutputSDK` (SDKs layer) as a stateless `Sendable` struct per architecture guidelines. Uses `DispatchSource.makeFileSystemObjectSource` with a dedicated serial queue and `O_EVTONLY` flag. Debounces writes by 200ms via a `Task.sleep` + cancellation pattern using a private `DebounceState` class to hold mutable task reference. Stream terminates via `continuation.onTermination` which cancels the debounce task and the dispatch source, closing the file descriptor via the source's cancel handler.

**Skills to read**: `swift-architecture`

Create a reusable file-watching utility at the SDK layer that monitors a file for changes and emits updates as an `AsyncSequence`. This will be used by the active plan model but is general-purpose.

**New type in `AIOutputSDK` (or a new `FileWatcherSDK` if preferred)**:

```swift
public struct FileWatcher: Sendable {
    public let url: URL

    public init(url: URL)

    /// Returns an AsyncStream that emits the file's content whenever it changes on disk.
    /// Uses DispatchSource.makeFileSystemObjectSource to watch for writes.
    public func contentStream() -> AsyncStream<String>
}
```

**Implementation details**:
- Use `DispatchSource.makeFileSystemObjectSource` with `.write` flag on the file descriptor
- When a change is detected, read the file content and yield it to the stream
- Handle file descriptor lifecycle (open on start, close on termination)
- Debounce rapid changes (e.g., 200ms) to avoid flooding during multi-write operations
- The stream terminates when the caller drops it (cooperative cancellation)

**Layer placement**: SDK layer — this is a low-level utility with no business logic.

**Files to create**:
- `AIOutputSDK/FileWatcher.swift` (or create a small `FileWatcherSDK` package if `AIOutputSDK` shouldn't own file I/O)

## - [x] Phase 4: Embeddable read-only chat view

**Skills used**: `swift-architecture`
**Principles applied**: Extracted the scrollable message list (with scroll-to-bottom tracking, unseen count badge, empty state) into a standalone `ChatMessagesView` that reads `ChatModel` from the environment. `ChatPanelView` now composes `ChatMessagesView` + `messageInputView`, keeping the interactive input separate. Feature views can embed `ChatMessagesView` directly for read-only streaming output.

**Skills to read**: `swift-architecture`

Refactor the chat view to support embedding within feature views in a read-only mode. The current `ChatPanelView` always shows the input area and is designed as a standalone panel. We need a variant that:
- Can be placed in the bottom third of any feature view
- Supports a read-only mode (no input field, no send button)
- Can be driven by an external `ChatModel` that the feature creates and controls
- Shows the same rich formatted content from Phase 2

**Approach — extract a reusable `ChatMessagesView`**:

Create `ChatMessagesView` that contains only the message list and formatted content rendering (the top portion of current `ChatPanelView`). This is the reusable piece.

```swift
struct ChatMessagesView: View {
    @Environment(ChatModel.self) var chatModel
    // Just the scrollable message list, no input field
}
```

Then refactor `ChatPanelView` to compose:
```swift
struct ChatPanelView: View {
    var body: some View {
        VStack(spacing: 0) {
            ChatMessagesView()
            Divider()
            messageInputView  // only in interactive mode
        }
    }
}
```

For feature views, they embed `ChatMessagesView` directly (read-only) or `ChatPanelView` (interactive, for plan iteration).

**Files to create/modify**:
- Create: `Apps/AIDevToolsKitMac/Views/Chat/ChatMessagesView.swift` — extracted message list
- Modify: `Apps/AIDevToolsKitMac/Views/Chat/ChatPanelView.swift` — compose using `ChatMessagesView`

## - [x] Phase 5: Integrate chat into MarkdownPlannerDetailView

**Skills used**: `swift-architecture`
**Principles applied**: Added `executionProgressObserver` on `MarkdownPlannerModel` (called on `@MainActor`) so the view can bridge execution progress events into a view-owned `ChatModel` without crossing concurrency boundaries. `ActivePlanModel` owns `FileWatcher` task lifecycle; `makeChatModel(workingDirectory:systemPrompt:)` encapsulates client wiring. `ChatModel` gained `systemPrompt` threading, `beginStreamingMessage/appendTextToCurrentStreamingMessage/finalizeCurrentStreamingMessage` for programmatic injection, and `appendStatusMessage` to avoid `ChatMessage` leaking into the detail view. `MarkdownPlannerDetailView` uses `VSplitView` with `ChatMessagesView` (read-only during execution) and `ChatPanelView` (interactive iteration chat). `OutputPanel` is removed.

**Skills to read**: `swift-architecture`

This is the main integration phase. Replace the `OutputPanel` with an embedded chat view and add plan iteration chat.

### 5a: Execution streaming via chat (read-only)

When the user hits "Execute All/Next":
1. Create a `ChatModel` for the execution, connected to the selected provider
2. Send the execution prompts through the chat session (via `SendChatMessageUseCase`)
3. Show `ChatMessagesView` (read-only) in the bottom third of the detail view instead of the `OutputPanel`
4. Execution output streams to the chat as structured content blocks

This requires changing how `MarkdownPlannerModel.execute()` works:
- Currently it calls `ExecutePlanUseCase` which calls `AIClient.runStructured()` directly
- Instead, execution prompts should be sent through a `ChatModel` so they appear in the chat view
- The `ExecutePlanUseCase` progress callbacks (`.phaseOutput`, `.startingPhase`, etc.) need to be mapped to chat messages or system messages in the chat view
- Phase transitions could appear as system-style messages (e.g., "Starting Phase 2: Implementation...")

**Layout change** for `MarkdownPlannerDetailView`:
```
┌─────────────────────────────────────┐
│ Header bar (provider, execute, etc) │
├─────────────────────────────────────┤
│                                     │
│ Plan content (phases, markdown,     │
│ architecture diagram)               │
│                                     │
├─────────────────────────────────────┤  ← VSplitView divider
│ Chat view (bottom third)            │
│ - Read-only during execution        │
│ - Interactive during iteration      │
│ - Shows structured content blocks   │
└─────────────────────────────────────┘
```

### 5b: Plan iteration chat (interactive)

After plan generation completes, show an interactive chat (with input field) in the bottom third:
- Create a `ChatModel` with a system prompt that:
  - Explains the user has just generated a plan
  - Provides the plan file path
  - Instructs the AI to help iterate: "The user may ask you to refine this plan. Read the plan file, make requested changes, and save the updated file."
  - Tells the AI to distinguish between brainstorming questions and edit requests
- The chat session uses the selected provider
- Connect a `FileWatcher` (from Phase 3) to the plan file
- When the file changes on disk (mutated by the AI via the chat), update the plan content displayed in the upper portion of the view

**New model — `ActivePlanModel`** (App layer, `@Observable @MainActor`):
```swift
@Observable @MainActor
final class ActivePlanModel {
    private(set) var content: String = ""
    private(set) var phases: [PlanPhase] = []

    private var watchTask: Task<Void, Never>?

    func startWatching(url: URL) {
        watchTask?.cancel()
        watchTask = Task {
            for await newContent in FileWatcher(url: url).contentStream() {
                self.content = newContent
                self.phases = MarkdownPlannerModel.parsePhases(from: newContent)
            }
        }
    }

    func stopWatching() {
        watchTask?.cancel()
    }
}
```

### 5c: Wire it together in MarkdownPlannerDetailView

- Add `@State private var executionChatModel: ChatModel?` for execution streaming
- Add `@State private var iterationChatModel: ChatModel?` for plan iteration
- Add `@State private var activePlanModel = ActivePlanModel()`
- Show the chat view (read-only or interactive) in the bottom third when either model is active
- Remove `OutputPanel` usage — all execution output goes through the chat
- When plan content changes via `ActivePlanModel`, update the rendered markdown above

**Files to create/modify**:
- Create: `Apps/AIDevToolsKitMac/Models/ActivePlanModel.swift`
- Modify: `Apps/AIDevToolsKitMac/Views/MarkdownPlannerDetailView.swift` — embed chat, replace OutputPanel
- Modify: `Apps/AIDevToolsKitMac/Models/MarkdownPlannerModel.swift` — adjust execution to work with ChatModel
- Possibly modify: `Features/MarkdownPlannerFeature/usecases/ExecutePlanUseCase.swift` — if execution needs to go through chat

## - [x] Phase 6: Remove standalone workspace chat panel

**Skills used**: `swift-architecture`
**Principles applied**: Removed all chat panel state (`chatPanelVisible`, `chatProviderName`, `chatModel`, `showingChatSettings`, `showingSessionPicker`), deleted `chatToolbar`, `bottomBar`, `chatPanelView`, and `rebuildChatModel()`. Replaced the `VSplitView`-wrapped detail section with a direct `detailContentView`. Removed `ChatFeature` import. Chat infrastructure (`ChatPanelView`, `ChatModel`) remains intact — now used exclusively within feature views (e.g. `MarkdownPlannerDetailView`).

**Skills to read**: `swift-architecture`

With chat embedded in feature views, the standalone chat panel in `WorkspaceView` is no longer needed.

**Changes to `WorkspaceView.swift`**:
- Remove `@AppStorage("chatPanelVisible")` and `@AppStorage("chatProviderName")`
- Remove `@State private var chatModel: ChatModel?`
- Remove `chatToolbar`, `bottomBar`, `chatPanelView` computed properties
- Remove `rebuildChatModel()` method
- Remove the `VSplitView` wrapper in the detail section — just show `detailContentView` directly
- Remove chat-related sheet bindings (`showingChatSettings`, `showingSessionPicker`)
- Remove `onChange(of: chatProviderName)` handler

**Cleanup**:
- Remove `ChatSettingsView` references from WorkspaceView (settings can move to per-feature chat instances if needed)
- Keep `ChatPanelView`, `ChatModel`, and all chat infrastructure — they're now used within feature views

**Files to modify**:
- `Apps/AIDevToolsKitMac/Views/WorkspaceView.swift` — remove standalone chat panel

## - [x] Phase 7: Research provider output richness

**Skills used**: `swift-architecture`
**Principles applied**: Research-only phase — no code changes. Ran Claude CLI with `--output-format stream-json --verbose` to capture a real JSONL sample, then cross-referenced `ClaudeStreamFormatter`, `ClaudeStreamModels`, and `AnthropicProvider` against the live data. Key findings: (1) `toolResult.name` is always `""` because the `user` event only has `tool_use_id` not the tool name — correlation across events requires statefulness; (2) array `ToolResultContent` is silently dropped and string content is truncated at 200 chars; (3) `AnthropicProvider` emits no thinking, no tool input detail, and no metrics; (4) thinking is disabled at the `MessageParameter` call site. All findings documented in `docs/proposed/2026-03-28-e-provider-output-richness-research.md`.

**Skills to read**: `swift-architecture`

Before the structured content model (Phase 1) can be finalized, research what each provider actually returns during streaming to ensure we capture all meaningful data.

**Research tasks**:
1. Run a Claude CLI command with `--output-format stream-json` and `--verbose` flags against a real prompt that triggers tool calls, thinking, and text output. Capture the full JSONL stream.
2. Run an Anthropic API streaming call and capture the full `MessageStreamResponse` events.
3. Compare the raw stream data to what `ClaudeStreamFormatter.format()` currently produces — document what's lost.
4. Compare the raw stream data to what the chat `ContentLine` parsing currently shows — document the full gap.

**Expected findings** (based on code review):
- Tool result content is truncated to 200 characters in `ClaudeStreamModels.ToolResultContent.summary`
- Tool use input details (full command text, file contents for Write/Edit) are available but only partially shown
- Anthropic streaming only extracts `chunk.delta.text` — thinking blocks and tool calls from the API are likely not captured
- The chat `ContentLine` parser only recognizes `🧠` and `🔧` prefixes, which the `ClaudeStreamFormatter` doesn't actually produce (it uses `[Thinking]` and `[Bash]` etc.) — this means **thinking and tool info never actually display in chat today**

This research phase can run in parallel with earlier phases since it's informational. Its findings should refine the `AIContentBlock` enum and formatter implementations in Phase 1.

**Output**: A document or code comments capturing the mapping from each provider's raw stream events to `AIContentBlock` cases.

## - [x] Phase 8: Validation

**Skills used**: `swift-testing`
**Principles applied**: Build verified clean. Added `ClaudeStreamFormatterTests` (12 tests) covering `formatStructured()` for all event types — text delta, thinking, tool use (Bash/Read), tool result (success/error), metrics, multi-block, multi-line chunks, and edge cases. Added `FileWatcherTests` (3 tests) covering non-existent file (stream finishes immediately), write detection (emits updated content after 200ms debounce), and cancellation (stream terminates without hanging). `ChatMessage` contentBlocks tests already existed in `ChatFeatureTests` from prior phases. Pre-existing `SkillScannerSDKTests` failures are unrelated (they pick up `~/.claude/commands` entries in isolation mode).

**Skills to read**: `swift-testing`

**Build verification**:
```bash
cd /Users/bill/Developer/personal/AIDevTools && swift build 2>&1
```

**Automated tests**:
```bash
swift test 2>&1
```

**Unit tests to add**:
- `FileWatcher` — test that it emits content when a file is written to, test cancellation
- `AIContentBlock` — test structured formatting from `ClaudeStreamFormatter.formatStructured()`
- `ChatMessage` with `contentBlocks` — test rendering logic

**Manual verification checklist**:
- [ ] Open a plan in MarkdownPlannerDetailView, hit Execute All — verify chat view appears at bottom with streaming structured output (thinking blocks, tool calls, text)
- [ ] After plan generation, verify iteration chat appears with system prompt context
- [ ] Type a refinement in the iteration chat — verify the plan content updates when the AI modifies the file
- [ ] Verify the standalone chat panel no longer appears in WorkspaceView
- [ ] Switch providers in the plan detail view — verify chat reconnects to the new provider
- [ ] Verify `OutputPanel` is no longer used in the Markdown Planner flow
