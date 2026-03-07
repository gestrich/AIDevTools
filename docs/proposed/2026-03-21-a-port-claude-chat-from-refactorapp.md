## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture (Apps, Features, Services, SDKs), layer placement, naming conventions, use case protocols |

## Background

AIDevTools and RefactorApp both have Claude/Anthropic integration, but built on different foundations:

- **AIDevTools** has three SDK-layer targets (`AnthropicSDK`, `ClaudeCLISDK`, `ClaudePythonSDK`) but only the Anthropic HTTP API path has a chat service and UI (`ChatService` + `ChatFeature`). These are built on `SwiftAnthropic` for direct API calls.

- **RefactorApp** has a full Claude Code CLI-based chat system: `ClaudeCodeClient` (SDK), `ClaudeService` (session management, message queuing, streaming), and `ClaudeUI` (rich chat with slash command autocomplete, custom keyboard handling, image paste support).

The current target names `ChatService` and `ChatFeature` are ambiguous — they don't indicate which Claude backend they use. As we add a second chat path (CLI-based), clear naming becomes essential.

### What to port from RefactorApp

1. **ClaudeService** (service layer) — Session-based chat orchestration on top of Claude CLI: session management, message queuing, streaming output parsing, `ChatMessage`/`SessionState`/`ImageAttachment` models, `ClaudeSettings`
2. **Slash command system** — `SlashCommandScanner` (scans `~/.claude/commands/` and `<project>/.claude/commands/` for `.md` files), `MessageInputWithAutocomplete`, `CommandAutocompleteView`, `CustomTextField`
3. **ClaudeView** — Rich chat UI with settings, session picker, queue viewer

### What NOT to port

- `ClaudeUsageService` / `ClaudeUsageFeature` (billing analytics)
- `ClaudeCodeStepExecutor` (workflow execution)
- `ClaudeCodeClient` SDK (AIDevTools already has `ClaudeCLISDK` which covers the same ground)

### Key architecture decision

RefactorApp's `ClaudeCodeClient` and AIDevTools' `ClaudeCLISDK` both shell out to `/usr/local/bin/claude` but have different APIs. Rather than porting `ClaudeCodeClient`, the new service layer will be adapted to use `ClaudeCLISDK` as its backing SDK. This avoids a redundant SDK target.

## Phases

## - [x] Phase 1: Rename existing chat targets for clarity

**Skills used**: `swift-architecture`
**Principles applied**: Alphabetical ordering maintained in Package.swift products, target dependencies, and imports

Rename the current Anthropic HTTP API chat targets to make their backend explicit:

| Current Name | New Name | Reason |
|-------------|----------|--------|
| `ChatService` | `AnthropicChatService` | Built on `AnthropicSDK`, manages Anthropic HTTP conversations |
| `ChatFeature` | `AnthropicChatFeature` | Use cases + UI for Anthropic HTTP chat |

Changes required:
- Rename directories: `Sources/Services/ChatService/` → `Sources/Services/AnthropicChatService/`, `Sources/Features/ChatFeature/` → `Sources/Features/AnthropicChatFeature/`
- Update `Package.swift`: target names, paths, dependencies, products
- Update all `import ChatService` / `import ChatFeature` references across the codebase (CLI commands, app views, other targets)
- Update `AIDevTools.xcodeproj/project.pbxproj` if it references these targets by name
- Verify the project builds after rename

## - [x] Phase 2: Add SlashCommandSDK target

**Skills used**: `swift-architecture`
**Principles applied**: Stateless `Sendable` struct per SDK conventions; `FileManager` as local variable to avoid Sendable warning; alphabetical ordering in Package.swift

Port the slash command scanner from RefactorApp as a new SDK target. This is a stateless scanner (single operation: scan a directory for `.md` files) — fits the SDK layer.

Source: `RefactorApp/services/ClaudeService/Sources/ClaudeService/SlashCommandScanner.swift`

New target: `SlashCommandSDK` at `Sources/SDKs/SlashCommandSDK/`

Files to create:
- `SlashCommand.swift` — `SlashCommand` model (name, path, id)
- `SlashCommandScanner.swift` — `SlashCommandScanner` struct (stateless, `Sendable`)
  - `scanCommands(workingDirectory:)` — scans global (`~/.claude/commands/`) and local (`<dir>/.claude/commands/`) directories
  - `filterCommands(_:query:)` — fuzzy scoring/filtering

Adaptations from RefactorApp:
- Make `SlashCommandScanner` a `struct` (not `final class`) to match SDK conventions (stateless, `Sendable`)
- Keep the scoring algorithm as-is (it's well-implemented)

Package.swift: add target with no dependencies, add product, add to alphabetical ordering.

## - [x] Phase 3: Add ClaudeCodeChatService target

**Skills used**: `swift-architecture`
**Principles applied**: Adapted ClaudeCLIClient.run() as SDK backing; added --continue/--resume flags to Claude command; removed AppKit dependency for portability; stripped useClaudeCodeSDK toggle (single SDK path)

Port the session-based chat service from RefactorApp as a new Service target. This manages stateful session data, message models, and settings — fits the Services layer.

Source files from `RefactorApp/services/ClaudeService/Sources/ClaudeService/`:
- `ChatMessage.swift` — `ChatMessage`, `ContentLine`, `ImageAttachment` models
- `ClaudeService.swift` — `ClaudeService` (@Observable, session management, message queuing)
- `ClaudeSettings.swift` — `ClaudeSettings` (@Observable, UserDefaults-backed)

New target: `ClaudeCodeChatService` at `Sources/Services/ClaudeCodeChatService/`

Files to create:
- `ClaudeCodeChatMessage.swift` — Ported `ChatMessage`, `ContentLine`, `ImageAttachment` (renamed to avoid collision with `AnthropicChatService.ChatMessage`)
- `ClaudeCodeChatSession.swift` — `SessionState`, `QueuedMessage` models
- `ClaudeCodeChatSettings.swift` — `ClaudeCodeChatSettings` (ported from `ClaudeSettings`)
- `ClaudeCodeChatManager.swift` — Main service class (ported from `ClaudeService`). Manages sessions, message queuing, streaming output from CLI

Key adaptation: RefactorApp's `ClaudeService` depends on `ClaudeCodeClient` (`ClaudeClientProtocol`). AIDevTools has `ClaudeCLISDK` which is a different API shape. The manager needs to be adapted to use `ClaudeCLISDK`'s `ClaudeCLIClient` instead. This means:
- Replace `ClaudeClientProtocol.sendInstructionsStreaming()` calls with `ClaudeCLIClient.run()`
- Map `ClaudeStreamModels` events to `ClaudeCodeChatMessage` content lines
- Session resume via `ClaudeCLIClient` flags (`--resume`, `--continue`)
- Remove the `ClaudeCodeSDKAdapter` toggle (not needed — `ClaudeCLISDK` already handles CLI invocation)

Dependencies: `ClaudeCLISDK`

**Note**: The `@Observable` annotation on `ClaudeService` violates the architecture principle ("@Observable at the App Layer only"). However, since we're porting existing code and this is how the RefactorApp service works, keep it for now and note it as a future refactor opportunity.

## - [x] Phase 4: Add ClaudeCodeChatFeature target

**Skills used**: `swift-architecture`
**Principles applied**: UseCase structs follow existing codebase convention (Sendable struct, Options, run()); actor-based text accumulation for Sendable safety; dependencies flow downward (Feature → Service → SDK)

Create use cases for the Claude Code CLI chat, following the `UseCase`/`StreamingUseCase` pattern.

New target: `ClaudeCodeChatFeature` at `Sources/Features/ClaudeCodeChatFeature/`

Use cases to create:
- `SendClaudeCodeMessageUseCase` — `StreamingUseCase` that sends a message through `ClaudeCodeChatManager` and streams progress (text deltas, tool use, thinking blocks). Options: message text, working directory, session ID (optional), images (optional).
- `ListClaudeCodeSessionsUseCase` — `UseCase` that lists available Claude Code sessions for a working directory. Wraps the session discovery from `ClaudeCodeChatManager`.
- `ScanSlashCommandsUseCase` — `UseCase` that scans for available slash commands. Wraps `SlashCommandSDK.SlashCommandScanner`.

Dependencies: `ClaudeCodeChatService`, `SlashCommandSDK`, `Uniflow` (if available, otherwise define locally)

## - [x] Phase 5: Add CLI commands

**Skills used**: `swift-architecture`
**Principles applied**: CLI commands consume use cases directly per architecture; alphabetical subcommand registration

**Skills to read**: `swift-architecture`

Add CLI commands to `AIDevToolsKitCLI` that expose the new Claude Code chat functionality.

Commands to add:
- `claude-chat` — Interactive REPL chat with Claude Code CLI (similar to RefactorApp's `ClaudeCLI/EntryPoint.swift`)
  - `--working-dir <path>` — Set working directory (defaults to cwd)
  - `--resume` — Resume last session
  - `--message <text>` — Single message mode (non-interactive)
- `slash-commands` — List available slash commands for a directory
  - `--working-dir <path>` — Directory to scan (defaults to cwd)

Both commands consume the use cases from Phase 4 directly.

Update `EntryPoint.swift` to register the new commands (keep alphabetical ordering).

Add `ClaudeCodeChatFeature` and `SlashCommandSDK` to `AIDevToolsKitCLI` dependencies.

## - [x] Phase 6: Add Claude Code chat UI to the Mac app

**Skills used**: `swift-architecture`
**Principles applied**: Views in Apps layer; @Observable ClaudeCodeChatManager injected via .environment(); ChatMode picker switches between API and CLI backends; removed JiraService dependency; ImageAttachment.toNSImage() extension in Apps layer for AppKit conversion

Port the ClaudeUI views from RefactorApp into the AIDevTools Mac app. Per the architecture, views and `@Observable` models live in the Apps layer.

Source files from `RefactorApp/ui-toolkits/ClaudeUI/Sources/ClaudeUI/`:
- `ClaudeView.swift` — Main chat view (messages, input, settings sheet, session picker, queue viewer)
- `CustomTextField.swift` — `NSViewRepresentable` for keyboard event handling
- `MessageInputWithAutocomplete.swift` — Text input with slash command autocomplete
- `CommandAutocompleteView.swift` — Autocomplete dropdown UI

Destination: `AIDevTools/Views/ClaudeCodeChat/` (in the Mac app target, not the package)

Adaptations:
- Replace `@Environment(ClaudeService.self)` with local `@State` or dependency injection from the app
- Replace `import ClaudeService` / `import ClaudeUI` with `import ClaudeCodeChatService` / `import SlashCommandSDK`
- Remove `JiraService` dependency (not relevant to AIDevTools)
- Wire into `WorkspaceView.swift` as a toggleable panel (similar to existing `ChatView` integration but for Claude Code backend)
- Add a picker or toggle in the workspace view to switch between Anthropic API chat and Claude Code CLI chat, or show them as separate tabs/panels

Update the settings view (`GeneralSettingsView.swift`) to include Claude Code chat settings (streaming, resume session, verbose mode, max thinking tokens).

## - [x] Phase 7: Update README.md documentation

**Skills used**: `swift-architecture`
**Principles applied**: Documented full target inventory organized by layer (SDKs, Services, Features) with what each wraps/builds on

Update `AIDevToolsKit/README.md` to document the full target inventory, especially the Claude/Anthropic targets.

Add a section after the existing Architecture section:

### Claude & Anthropic Targets

Document each target with its layer, purpose, and what it wraps:

**SDKs (stateless, single-operation wrappers):**
| Target | Wraps | Description |
|--------|-------|-------------|
| `AnthropicSDK` | SwiftAnthropic HTTP API | Direct Anthropic Messages API — send messages, stream responses, tool calling |
| `ClaudeCLISDK` | `/usr/local/bin/claude` binary | Claude Code CLI subprocess — structured output, stream-json parsing, result events |
| `ClaudePythonSDK` | Python `claude_agent.py` script | Claude Agent via Python subprocess — JSON stdin/stdout, inactivity watchdog |
| `SlashCommandSDK` | Filesystem scan | Scans `~/.claude/commands/` and project `.claude/commands/` for slash command `.md` files |

**Services (shared models, config, stateful utilities):**
| Target | Built On | Description |
|--------|----------|-------------|
| `AnthropicChatService` | `AnthropicSDK` | Anthropic HTTP chat — orchestration, SwiftData persistence, streaming events |
| `ClaudeCodeChatService` | `ClaudeCLISDK` | Claude Code CLI chat — session management, message queuing, content line parsing |

**Features (use case orchestration):**
| Target | Description |
|--------|-------------|
| `AnthropicChatFeature` | Use cases for Anthropic HTTP chat (send message, manage conversations) |
| `ClaudeCodeChatFeature` | Use cases for Claude Code CLI chat (send message, list sessions, scan slash commands) |

## - [x] Phase 8: Validation

**Skills used**: `swift-testing`
**Principles applied**: Arrange/Act/Assert pattern; tests use temp directories with cleanup; 281 total tests pass (23 new)

**Skills to read**: `swift-testing`

Validation approach:

- **Build**: `swift build` must succeed with all new and renamed targets
- **Existing tests**: `swift test --skip EvalIntegrationTests` must pass (renames shouldn't break tests, but verify imports are updated)
- **New unit tests**:
  - `SlashCommandSDKTests` — Test scanner finds `.md` files, filter/scoring works correctly, handles missing directories
  - `ClaudeCodeChatServiceTests` — Test message model parsing (content lines, thinking/tool/text), session state management, settings defaults
  - `ClaudeCodeChatFeatureTests` — Test use case wiring with mock SDK clients
- **Manual verification**:
  - Run the Mac app, toggle the Claude Code chat panel, verify it appears
  - Run `swift run ai-dev-tools-kit slash-commands` and verify it lists commands
  - Run `swift run ai-dev-tools-kit claude-chat --message "hello"` with a valid Claude CLI installation
- **Xcode project**: Open `AIDevTools.xcodeproj`, verify all targets resolve, app builds and runs
