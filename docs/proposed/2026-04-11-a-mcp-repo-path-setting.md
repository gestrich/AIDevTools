## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | 4-layer rules — settings models stay in Apps, logic in Services |
| `ai-dev-tools-composition-root` | How to wire new models at startup and inject into views |
| `ai-dev-tools-configuration-architecture` | Where settings live (UserDefaults for app-wide non-sensitive) |
| `ai-dev-tools-enforce` | Run after all phases complete to verify no violations |

## Background

The MCP server (`ai-dev-tools-kit mcp`) must be reachable by external clients (the Mac app's chat panels, Claude CLI). Currently the CLI self-registers its own path to `~/Library/Application Support/AIDevTools/mcp-config.json` on every invocation — but if the user hasn't run the CLI yet, the config is stale or missing.

The better approach: add a one-time setting for the AIDevTools repo path. From that the Mac app can derive the CLI binary path deterministically (`<repoPath>/AIDevToolsKit/.build/debug/ai-dev-tools-kit`), write the MCP config itself, and show a staleness indicator so the user knows when they need to rebuild.

Goals:
- Mac app writes MCP config from the repo path setting — no CLI run required
- Chat panel shows a clear message when MCP is not configured
- Chat panel shows "built N days ago" with a help icon when the binary is stale
- CLI self-registration in `EntryPoint.main()` is kept as a belt-and-suspenders fallback

## Phases

## - [x] Phase 1: Add `aiDevToolsRepoPath` to `SettingsModel`

**Skills used**: `ai-dev-tools-configuration-architecture`
**Principles applied**: Followed the same `UserDefaults`-backed pattern as `dataPath`. Added the property, key constant, and update method to `SettingsModel`, loaded it in `init()`, and added a "AIDevTools Repo Path" row to `GeneralSettingsView` with Choose/Clear buttons and a secondary binary path display.

**Skills to read**: `ai-dev-tools-configuration-architecture`

Add an optional `URL` property to `SettingsModel` (alongside the existing `dataPath`) backed by `UserDefaults`:

```swift
static let aiDevToolsRepoPathKey = "AIDevTools.aiDevToolsRepoPath"

private(set) var aiDevToolsRepoPath: URL?

func updateAIDevToolsRepoPath(_ newPath: URL?) {
    aiDevToolsRepoPath = newPath
    UserDefaults.standard.set(newPath?.path, forKey: Self.aiDevToolsRepoPathKey)
}
```

Load it in `init()` alongside the existing `dataPath` load.

Add a "AIDevTools Repo Path" row to the existing settings UI (wherever `dataPath` is currently edited):
- When set, shows the resolved binary path below it as secondary text
- A "Choose…" button opens an `NSOpenPanel` (directory picker)
- A "Clear" button sets it back to nil

## - [x] Phase 2: Add `MCPStatus` and `MCPModel`

**Skills used**: `ai-dev-tools-composition-root`
**Principles applied**: Created `MCPStatus` enum and `MCPModel` in the Apps layer. `status` is a computed property resolving two binary candidates (Xcode sibling and Swift build from repo path) and picking the most recently modified. `writeMCPConfigIfNeeded()` writes JSON in the same format as the CLI's fallback writer.

**Skills to read**: `ai-dev-tools-composition-root`

Create `Sources/Apps/AIDevToolsKitMac/Models/MCPModel.swift`.

Define a status enum:

```swift
enum MCPStatus {
    case notConfigured
    case binaryMissing
    case ready(binaryURL: URL, builtAt: Date)

    var daysStale: Int? {
        guard case .ready(_, let builtAt) = self else { return nil }
        return Calendar.current.dateComponents([.day], from: builtAt, to: .now).day
    }
}
```

Create `@MainActor @Observable final class MCPModel`:
- `init(settingsModel: SettingsModel)`
- Computed `status: MCPStatus` — resolves the binary by checking two candidate paths and picking the most recently modified one that exists:
  1. **Xcode build (sibling)**: `Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("ai-dev-tools-kit")` — always checked, no setting required
  2. **Swift build**: `<settingsModel.aiDevToolsRepoPath>/AIDevToolsKit/.build/debug/ai-dev-tools-kit` — only checked when repo path is set
  - If neither exists → `.binaryMissing`
  - If repo path is not set and sibling doesn't exist → `.notConfigured`
  - Otherwise → `.ready(binaryURL: mostRecent, builtAt: modificationDate)`
- `func writeMCPConfigIfNeeded()` — when status is `.ready`, writes JSON to `DataPathsService.mcpConfigFileURL` (same format as CLI's `writeMCPConfig`)

`MCPModel` lives in the Apps layer. It has no network calls and no async work.

## - [x] Phase 3: Wire `MCPModel` into `CompositionRoot`

**Skills used**: `ai-dev-tools-composition-root`
**Principles applied**: Added `mcpModel: MCPModel` to `CompositionRoot`, constructed it in `create()` with the existing `settingsModel` and called `writeMCPConfigIfNeeded()` at startup. Injected into the SwiftUI environment via `AIDevToolsKitMacEntryView`. Used `.onChange(of: settingsModel.aiDevToolsRepoPath)` in the view body to re-trigger config writing when the user updates the repo path setting.

In `CompositionRoot`:
- Add `let mcpModel: MCPModel` property
- In `create()`: construct `MCPModel(settingsModel: settingsModel)`, call `mcpModel.writeMCPConfigIfNeeded()`
- Inject `mcpModel` into the SwiftUI environment so chat panels can read status

When `SettingsModel.aiDevToolsRepoPath` changes (user picks a new path in settings), call `mcpModel.writeMCPConfigIfNeeded()` again. Wire this via `.onChange` at the app entry point or by having `MCPModel` observe `SettingsModel` reactively via `withObservationTracking`.

## - [ ] Phase 4: MCP status UI in `ContextualChatPanel`

**Skills to read**: `ai-dev-tools-architecture` (views stay thin)

In `ContextualChatPanel`:

1. Read `MCPModel` from the environment: `@Environment(MCPModel.self) private var mcpModel`

2. In `rebuildChatModel()`, pass `mcpConfigPath` conditionally:
   - `.ready`: pass `DataPathsService.mcpConfigFileURL.path`
   - `.notConfigured` or `.binaryMissing`: pass `nil`

3. Add an MCP status row in the header bar (or just below it):
   - `.notConfigured`: amber inline banner — "MCP unavailable — set AIDevTools Repo Path in Settings"
   - `.binaryMissing`: amber banner — "MCP binary not found. Build the app in Xcode or run `swift build --target AIDevToolsKitCLI` in the repo."
   - `.ready` with `daysStale > 3`: info icon button — tapping shows popover "MCP binary last built N days ago. Run `swift build` to update."
   - `.ready` with `daysStale <= 3`: no UI (working fine)

Keep the view logic minimal — `MCPStatus` carries all the data, the view just renders it.

## - [ ] Phase 5: Create chat feature doc

Create `docs/features/chat/chat.md` covering:
- What the chat feature does (AI chat with streaming responses, session history, image attachments)
- MCP integration — what it enables, how to configure it (set AIDevTools Repo Path in Settings)
- The staleness indicator — what it means and how to resolve it (`swift build --target AIDevToolsKitCLI`)
- Provider selection (Anthropic API, Claude Code CLI, Codex)

Also update `README.md`'s AI Chat section to link to `docs/features/chat/chat.md`.

## - [ ] Phase 6: Update stale comments

Update the `ContextualChatPanel` docstring (currently says "MCP config is written once at app startup (CompositionRoot)") to reflect that config is written by `MCPModel` on startup and on repo path change.

Update the CLI's `EntryPoint.main()` comment to note that CLI self-registration is a fallback — the Mac app is now the primary writer when the repo path is configured.

## - [ ] Phase 7: Enforce

**Skills to read**: `ai-dev-tools-enforce`

Run the enforce skill across all files changed in this plan:
- `SettingsModel.swift`
- Settings UI file (wherever data path picker lives)
- `MCPModel.swift` (new)
- `CompositionRoot.swift`
- `ContextualChatPanel.swift`
- `EntryPoint.swift`
- `docs/features/chat/chat.md` (new)
