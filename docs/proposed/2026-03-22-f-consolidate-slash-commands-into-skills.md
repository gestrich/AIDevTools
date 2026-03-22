## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | Architecture guidance for layer responsibilities and dependency rules |

## Background

The legacy `.claude/commands/` directory predates the `.claude/skills/` (and `.agents/skills/`) convention. The app currently has a separate `SlashCommandSDK` framework alongside the skills framework. Since commands have been superseded by skills, the app should treat both locations uniformly and remove the redundant slash command infrastructure.

---

## Phases

## - [x] Phase 1: Inventory the Overlap

Audit `SlashCommandSDK` and the skills framework to understand:

- What `SlashCommandSDK` provides that the skills framework doesn't
- Where slash commands are referenced in the Mac app and CLI
- What chat autocomplete depends on from `SlashCommandSDK`

### Findings

#### SlashCommandSDK provides (that the skills framework doesn't)

| Capability | SlashCommandSDK | Skills Framework |
|---|---|---|
| **Fuzzy query filtering** | `filterCommands(_:query:)` with 4-level scoring (exact segment, prefix, substring, full-name) | None — returns all found skills |
| **Global user commands** | Scans `~/.claude/commands/` | Only scans repo-local `.agents/skills/` and `.claude/skills/` |
| **Flat file model** | Each command is a single `.md` file with a `/`-prefixed name | Supports both flat `.md` files and directories with `SKILL.md` + reference files |

#### Where slash commands are referenced

**SDK sources** (`Sources/SDKs/SlashCommandSDK/`):
- `SlashCommand.swift` — data model (name, path)
- `SlashCommandScanner.swift` — discovery from local + global dirs, fuzzy filtering

**Feature layer** (`Sources/Features/ClaudeCodeChatFeature/`):
- `ScanSlashCommandsUseCase.swift` — wraps scanner in a use case, takes working directory + optional query

**CLI** (`Sources/Apps/AIDevToolsKitCLI/`):
- `SlashCommandsCommand.swift` — `ai-dev-tools-kit slash-commands` subcommand, lists discovered commands

**Mac app** (`Sources/Apps/AIDevToolsKitMac/`):
- `MessageInputWithAutocomplete.swift` — creates `SlashCommandScanner`, calls `scanCommands()` on launch and `filterCommands()` as user types
- `CommandAutocompleteView.swift` — renders autocomplete dropdown (top 5 matches, keyboard nav, tab to insert)
- `ClaudeCodeChatView.swift` — imports `SlashCommandSDK` (indirect, via `MessageInputWithAutocomplete`)

**Tests**:
- `SlashCommandScannerTests.swift` — 6 test cases covering scanning, filtering, sorting
- `ClaudeCodeChatFeatureTests.swift` — tests `ScanSlashCommandsUseCase`

#### What chat autocomplete depends on from SlashCommandSDK

The autocomplete chain is:

1. `MessageInputWithAutocomplete` holds a `SlashCommandScanner` instance and `[SlashCommand]` state
2. On appearance / working directory change → `scanCommands(workingDirectory:)` loads all commands
3. On each keystroke starting with `/` → `filterCommands(_:query:)` returns scored matches
4. `CommandAutocompleteView` renders the filtered `[SlashCommand]` array (name display, selection highlight)
5. Tab/click inserts the selected command's `name` into the text field

**To migrate autocomplete**, the skills framework needs:
- A `filterSkills(_:query:)` method with equivalent fuzzy scoring
- Global skill scanning (or at minimum, scanning `~/.claude/commands/` as a legacy location)
- The `Skill` / `SkillInfo` model already has `name` and `path`, so the data model is compatible

## - [x] Phase 2: Extend Skills Framework

Update the skills framework to also scan `.claude/commands/` (and `.agents/commands/` if applicable) and treat entries there as skills. Ensure the skill model can represent everything a legacy command could.

### Changes

- `SkillScanner.scanSkills(at:globalCommandsDirectory:)` now scans four directory types in priority order:
  1. `.agents/skills` and `.claude/skills` (highest — existing behavior)
  2. `.agents/commands` and `.claude/commands` (local commands, lower priority)
  3. Optional `globalCommandsDirectory` parameter for `~/.claude/commands/` (lowest priority)
- Commands directories are scanned recursively — subdirectories create path-segmented names (e.g., `deploy/staging.md` → skill named `deploy/staging`)
- Skills override commands with the same name; `.agents/` variants override `.claude/` variants; local commands override global commands
- The `SkillInfo` model was sufficient as-is — no changes needed
- The `globalCommandsDirectory` parameter defaults to `nil`, preserving backward compatibility for existing callers
- 8 new tests cover: commands discovery, recursive nesting, priority/override behavior, global commands, and non-markdown filtering

## - [x] Phase 3: Migrate Consumers

Update the Mac app and CLI to use the skills framework everywhere slash commands were used:

- Chat autocomplete should use skills instead of slash commands
- Any UI referencing "commands" should use consistent "skills" terminology
- Remove imports of `SlashCommandSDK` from consuming modules

### Changes

- **SkillScanner** gained `filterSkills(_:query:)` — the fuzzy scoring algorithm ported from `SlashCommandScanner` (exact segment, prefix, substring, full-name tiers)
- **SkillInfo** now conforms to `Identifiable` (id = name) for direct SwiftUI usage
- **ScanSlashCommandsUseCase** → **ScanSkillsUseCase** — uses `SkillScanner` instead of `SlashCommandScanner`, passes `~/.claude/commands` as `globalCommandsDirectory` to preserve global command discovery
- **MessageInputWithAutocomplete** — replaced `SlashCommandScanner`/`SlashCommand` with `SkillScanner`/`SkillInfo`; skill names display with `/` prefix in the UI
- **CommandAutocompleteView** → **SkillAutocompleteView** — updated types and terminology
- **ClaudeCodeChatView** — removed `import SlashCommandSDK`
- **SlashCommandsCommand** (CLI) — now uses `ScanSkillsUseCase` internally; output uses "skills" terminology
- **Package.swift** — replaced `SlashCommandSDK` dependency with `SkillScannerSDK` in `AIDevToolsKitMac`, `ClaudeCodeChatFeature`, and `ClaudeCodeChatFeatureTests`
- **ClaudeCodeChatFeatureTests** — migrated to `ScanSkillsUseCase`/`SkillInfo` types; all tests updated
- No consumer module imports `SlashCommandSDK` after this phase; the SDK itself remains for Phase 4 removal

## - [x] Phase 4: Remove SlashCommandSDK

Delete the `SlashCommandSDK` target from `Package.swift` and remove its source files.

### Changes

- Removed `SlashCommandSDK` product, target, and `SlashCommandSDKTests` test target from `Package.swift`
- Deleted `Sources/SDKs/SlashCommandSDK/` (2 files: `SlashCommand.swift`, `SlashCommandScanner.swift`)
- Deleted `Tests/SDKs/SlashCommandSDKTests/` (1 file: `SlashCommandScannerTests.swift`)
- Verified no remaining imports or references to `SlashCommandSDK` in the codebase

## - [x] Phase 5: Validation

- Verify autocomplete in the chat input still works for both `/skills/` and `/commands/` entries
- Run the app and confirm no references to the removed framework
- Build all targets to confirm clean compilation

### Changes

- Confirmed no `.swift` files import or reference `SlashCommandSDK` — all remaining mentions are in documentation (historical phase notes)
- Updated `README.md`: replaced `SlashCommandSDK` row with `SkillScannerSDK` in the SDK table, updated `ClaudeCodeChatFeature` description from "scan slash commands" to "scan skills"
- Renamed `CommandAutocompleteView.swift` → `SkillAutocompleteView.swift` to match the `SkillAutocompleteView` struct inside
- All 17 `SkillScannerSDKTests` pass (scanning, filtering, priority/override, global commands)
- `swift build` succeeds cleanly across all targets
