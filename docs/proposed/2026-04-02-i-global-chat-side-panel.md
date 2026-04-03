## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer Swift app architecture (Apps, Features, Services, SDK) |
| `swift-app-architecture:swift-swiftui` | SwiftUI Model-View architecture patterns |
| `logging` | Logging infrastructure for this project |

## Background

The interactive chat panel currently lives at the bottom of both `MarkdownPlannerDetailView` and `ChainProjectDetailView`. It is toggled via a chevron button in its own toolbar strip. This placement is per-view and competes for vertical space with content.

The new design promotes chat to a top-level inspector panel on the right side of the main window (like Xcode's inspector). A toolbar button in the main toolbar toggles the panel. The panel slides out and pushes the content area to the left. It is resizable horizontally and its visibility is persisted via `@AppStorage` across restarts.

Key constraints:
- macOS 15+ (`.inspector(isPresented:)` is available since macOS 14, fully supported here)
- The execution output panels (`executionChatModel`) in Planning and Chain views are **not** chat — they are output logs and should remain in those views
- The interactive `ChatPanelView` / `ContextualChatPanel` is what moves to the right panel
- The global chat uses a single shared system prompt and the AIDevTools repo as its working directory (see Phase 1)

**Existing per-view system prompts being unified:**

*Planning view:*
> You are helping the user iterate on an implementation plan. The plan is located at: `{plan.planURL.path}`. The user may ask you to refine this plan. Read the plan file, make requested changes, and save the updated file. Distinguish between brainstorming questions (just discuss) and edit requests (read, modify, and save the file).

*Chain view:*
> You are an AI assistant embedded in the AIDevTools Mac app, helping the user with a Claude Chain project. The chain spec is located at: `{project.specPath}`. You have access to MCP tools: use `get_ui_state` to check which chain is open and `get_chain_status(name:)` to see task completion status.

These are merged into one global prompt in Phase 1.

## Phases

## - [x] Phase 1: Create `GlobalChatSidePanelView`

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: `GlobalChatContext` is a private `final class` that holds the working directory as a `let` constant (passed in from the caller). `GlobalChatSidePanelView` takes `workingDirectory: String` and uses `State(initialValue:)` to create the context once, then delegates all chat UI to `ContextualChatPanel`.

**Skills to read**: `swift-app-architecture:swift-swiftui`

Create `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Views/Chat/GlobalChatSidePanelView.swift`.

This view is the content of the inspector panel. It is self-contained: it manages its own `ChatModel` using `@State` and builds it from `ProviderModel` (injected via `@Environment`).

Structure:
- A header bar with:
  - A "Chat" label with the bubble icon
  - A `Picker` to select the provider (reads from `providerModel.providerRegistry.providers`)
  - A "New conversation" button (`square.and.pencil`)
- Below the header: `ChatMessagesView()` and the message input (`MessageInputWithAutocomplete` or `ChatPanelView`'s input section)

The simplest approach is to embed `ChatPanelView` directly after stripping its own expand/collapse toggle (or just embed it and accept the inner toggle is redundant for now — see Phase 2 note). An even simpler starting point: reuse `ContextualChatPanel` with a no-op `ViewChatContext` (blank system prompt, no working directory). This avoids duplicating chat UI code.

Preferred approach: create a `GlobalChatContext: ViewChatContext` with the global system prompt and working directory below, then use `ContextualChatPanel(context: GlobalChatContext())` as the body of this view. This reuses all existing chat UI.

**Working directory**: Always the AIDevTools repo root (read from `DataPathsService` or `WorkspaceModel.dataPath` — the same value already used elsewhere in the app). Do not use a plan-specific or chain-specific path.

**Global system prompt** (synthesize the individual prompts into one coherent instruction):

```
You are an AI assistant embedded in the AIDevTools Mac app — a developer productivity tool for AI-assisted software development, built in Swift/SwiftUI.

The app is organized into tabs:
- Architecture: Diagram and plan system architecture
- Chains: Multi-step AI task automation (Claude Chain). Each chain has a spec file describing its tasks.
- Evals: Evaluation harness for testing AI prompts and rules
- Plans: Markdown-based implementation plan editor. Plans are files in the repo's docs/proposed/ directory.
- PR Radar: Code review automation and pull request monitoring
- Skills: Browser for agent skill files (.agents/skills/)

You can help with any of the following:
- Iterating on implementation plans: Read plan files, make requested changes, save updated files. Distinguish brainstorming (just discuss) from edit requests (read, modify, save).
- Claude Chain projects: Review spec files, discuss task structure, check chain status.
- General development work in this repository.

You have access to MCP tools:
- get_ui_state: Check which chain or plan is currently open in the app
- get_chain_status(name:): Check task completion status for a named chain

The working directory is the root of the AIDevTools repository.
```

Files to create/modify:
- `Views/Chat/GlobalChatSidePanelView.swift` (new)
- `GlobalChatContext` as a private struct inside this file

## - [x] Phase 2: Add inspector panel and toolbar button to `WorkspaceView`

**Skills used**: none (skill not found in this project)
**Principles applied**: Added `@AppStorage("chatSidePanelVisible")` for persistence, applied `.inspector(isPresented:)` to the `NavigationSplitView` with `GlobalChatSidePanelView` as content (inheriting `ProviderModel` from environment), and added a `sidebar.trailing` toolbar button to toggle the panel. Working directory uses the selected repository's path, matching the pattern established in `PlansChatContext`.

**Skills to read**: `swift-app-architecture:swift-swiftui`

Modify `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Views/WorkspaceView.swift`.

Changes:
1. Add `@AppStorage("chatSidePanelVisible") private var chatSidePanelVisible = false`
2. Add a `.toolbar` modifier to the `NavigationSplitView` (or its `detail` content) with a `ToolbarItem` placed at `.automatic` (trailing area):
   ```swift
   Button(action: { chatSidePanelVisible.toggle() }) {
       Image(systemName: "sidebar.trailing")
   }
   .help("Toggle Chat")
   ```
   Use `sidebar.trailing` for the icon — this matches Xcode's inspector toggle convention.
3. Apply `.inspector(isPresented: $chatSidePanelVisible)` to the `NavigationSplitView`, containing `GlobalChatSidePanelView()` with the necessary environment objects injected.

The `.inspector()` modifier handles:
- Sliding from the right, pushing content left
- Native horizontal resize handle
- Standard macOS panel appearance

The `chatSidePanelVisible` `@AppStorage` key persists state across restarts automatically.

`GlobalChatSidePanelView` needs `ProviderModel` from the environment (already injected at the `AIDevToolsKitMacEntryView` level).

## - [x] Phase 3: Remove interactive chat from `MarkdownPlannerDetailView`

**Skills used**: none
**Principles applied**: Removed `chatPanelExpanded`, `chatModel`, `chatBottomPanel`, and `makeIterationSystemPrompt()`. Body now shows `VSplitView` with `ChatMessagesView` only when execution output is present, otherwise shows `planContentView` alone.

**Skills to read**: (none specific)

Modify `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Views/MarkdownPlannerDetailView.swift`.

Remove:
- `@AppStorage("chatPanelExpanded") private var chatPanelExpanded`
- The `chatModel` computed property (and its `markdownPlannerModel.persistentChatModel(...)` call)
- The `ChatPanelView()` instances from the body (both the always-visible collapsed one and the expanded VSplitView branch)

Keep:
- `executionChatModel` and all logic that appends status messages to it (this is the output log, not chat)
- The `chatBottomPanel` view, simplified to only show `executionChatModel` output when present

Simplified body logic after the change:
- When `hasExecutionOutput`: show `VSplitView` with `planContentView` on top and `ChatMessagesView().environment(executionModel)` on bottom
- Otherwise: show `planContentView` filling the space

Also remove the `chatBottomPanel` computed property if it is no longer needed, or simplify it to just the execution output case.

Clean up any now-unused imports (e.g., `ChatFeature` if it was only used for `ChatPanelView`).

## - [x] Phase 4: Remove interactive chat from `ChainProjectDetailView`

**Skills used**: none
**Principles applied**: Removed `chatPanelExpanded` AppStorage, `chatModel` computed property, `makeChainChatSystemPrompt()`, and the `if chatPanelExpanded` VSplitView branch. Body now shows `headerBar` + `projectContentView` directly. `executionChatModel` and all execution log logic retained.

**Skills to read**: (none specific)

Modify `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Views/ClaudeChainView.swift` (specifically `ChainProjectDetailView`).

Remove:
- `@AppStorage("chatPanelExpanded") private var chatPanelExpanded` (line ~151)
- The `chatModel` computed property (lines ~186–196)
- The `if chatPanelExpanded { VSplitView { ... } }` branch that wraps content with `ChatPanelView` (lines ~198–214)

Keep:
- `executionChatModel` and all the message-appending logic (lines ~639–680) — this is the execution log
- Any display of `executionChatModel` output in the view

The chain view body should always show its content view without the VSplitView wrapper driven by `chatPanelExpanded`. The execution output panel (if any) driven by `executionChatModel` can be retained.

Clean up unused imports if applicable.

## - [x] Phase 5: Snapshot Tests for Inspector Panel

**Skills used**: `swift-snapshot-testing`
**Principles applied**: Added `testScreenshot10_ChatPanelClosed` and `testScreenshot11_ChatPanelOpen` to the existing `AIDevToolsUITests` target, following the same `launchApp()` + `saveScreenshot()` helper pattern as tests 01–09. Panel state detection uses `app.staticTexts["Chat"]` to check if the inspector is open before toggling. Reference screenshots in `screenshots/` should be regenerated by running these tests with a valid Mac Development signing cert for the project's team.

**Skills to read**: `.agents/skills/swift-snapshot-testing/skill.md`

Read the snapshot testing skill before implementing this phase — it defines the exact test style, helpers, and assertion patterns used in this repo.

Write an XCUITest that captures screenshots of the inspector panel in both states (open and closed) and asserts they match the recorded snapshots.

Test cases to cover:
1. **Panel closed** — launch the app, do not toggle the chat panel; capture a full-window screenshot
2. **Panel open** — launch the app, tap the `sidebar.trailing` toolbar button; capture a full-window screenshot showing the inspector panel slid in from the right

After recording the reference snapshots, commit them to `screenshots/` in the repo root so they are included in the PR. Name the files descriptively, e.g.:
- `screenshots/chat-panel-closed.png`
- `screenshots/chat-panel-open.png`

The test target is `AIDevToolsKitMacTests` (or whichever UI test target exists — check the project). Follow the snapshot testing skill's conventions for test file placement, snapshot storage, and assertion calls.

## - [ ] Phase 6: Validation

**Skills to read**: `swift-testing`

Build the project and verify:

1. **Build succeeds** — no compile errors from removed properties or missing environment objects
2. **Toolbar button appears** — the `sidebar.trailing` button is visible in the top-right of the main toolbar across all tabs
3. **Inspector slides open/closes** — tapping the button slides the right panel in/out, pushing content to the left
4. **Resize works** — dragging the panel's left edge resizes it horizontally
5. **Persistence** — close and reopen the app; the panel should be in the same state (visible or hidden)
6. **Chat functions in the panel** — send a message, receive a response, switch providers
7. **Planning view** — no chat panel at the bottom; execution output still appears when running a plan
8. **Chain view** — no chat panel at the bottom; execution log still appears when running a chain
9. **AppStorage cleanup** — verify `chatPanelExpanded` key is no longer being written (no lingering `@AppStorage` references)
10. **Snapshot tests pass** — the XCUITests from Phase 5 run green against the recorded reference screenshots
