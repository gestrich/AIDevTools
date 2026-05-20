## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | 4-layer architecture rules — keep scanner SDK pure, use case in Features, CLI/Mac wiring in Apps |
| `ai-dev-tools-code-quality` | Avoid force unwraps, hidden fallbacks, raw strings as shared identifiers |
| `ai-dev-tools-composition-root` | Where defaults for global skill paths should live and how they flow to Mac app + CLI |
| `ai-dev-tools-enforce` | Final verification pass over all files touched by this plan |
| `ai-dev-tools-swift-testing` | Conventions for unit tests covering the expanded scanner |
| `ai-dev-tools-ui-tests` | Optional screenshot test to confirm user-source skills render in the Mac Skills tab |
| `swift-architecture` | General reference when adding inputs to a use case and threading them through the Apps layer |

## Background

The Mac app exposes a Skills tab and the CLI exposes a `skills` command. Both rely on `LoadSkillsUseCase`, which delegates to `SkillScanner.scanSkills(at:globalCommandsDirectory:)` in `SkillScannerSDK`.

Today the scanner discovers:
- **Project skills** — folders containing `SKILL.md` (or top-level `*.md` files) under `<repo>/.agents/skills` and `<repo>/.claude/skills`.
- **Project commands** — `*.md` files under `<repo>/.agents/commands` and `<repo>/.claude/commands`.
- **User commands** — `*.md` files under `~/.claude/commands` (default `SkillScanner.defaultGlobalCommandsDirectory`).

`~/.agents/skills` exists on Bill's machine (e.g. `claude-chain`, `docc`, `grill-me`, `incremental-integration`, `slack-message`, `text-me`, ...) and `~/.claude/skills` may exist as a symlink/sibling, but neither is scanned today. The result is the Mac app's Skills tab and the CLI `skills` command miss every globally-installed skill.

The fix is to teach the scanner to also walk user-level skill directories, thread their paths through `LoadSkillsUseCase`, and supply sensible defaults from both the Mac app and the CLI composition roots. Skills already carry `SkillSource` (`.project` / `.user`), so the data model needs no change — but the UI should make the source visible so Bill can tell at a glance where a skill came from.

### Constraints / decisions worth pinning down

- **Defaults**: `~/.agents/skills` and `~/.claude/skills` (mirrors how project skills work under both `.agents/skills` and `.claude/skills`).
- **Deduplication**: keep the existing visited-path + name dedup so a `.claude/skills -> .agents/skills` symlink at the home level doesn't double-list entries (mirrors the project-skill loop).
- **Precedence**: project skills should win over user skills when names collide. The scanner already filters by `seen.insert($0.name)` after sorting alphabetically — that order is name-based, not source-based, so we need an explicit precedence pass before final dedup. See Phase 1.
- **Source label**: assign `.user` to skills found under the global skill dirs; reuse the existing `SkillSource` enum.
- **Mac app**: Skills tab shows a flat list today. Add a small badge (e.g. "user" tag) next to user-source skills so Bill can distinguish them without changing the selection model.
- **CLI**: `skills` command already prints `name (source)`, so no behavior change required beyond the new entries appearing.

## Phases

## - [x] Phase 1: Extend `SkillScanner` to walk user-level skill directories

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-code-quality`
**Principles applied**: Kept the scanner SDK pure (no Apps/Features types leaked in). Extracted the project-skill loop into a private `scanSkillsDirectory(_:source:visited:)` helper reused for both project and user dirs. Added a stable project-before-user partition prior to name dedup so precedence is explicit instead of an alphabetical accident. Threaded the shared `visited` set through the helper so a `~/.claude/skills -> ~/.agents/skills` symlink can't double-walk. New parameter defaults to `defaultGlobalSkillsDirectories`, so existing call sites compile unchanged.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-code-quality`

- Add a static `defaultGlobalSkillsDirectories: [URL]` to `SkillScanner` (in `SDKs/SkillScannerSDK/SkillScanner.swift`) pointing at `~/.agents/skills` and `~/.claude/skills`.
- Extend the public `scanSkills` API:
  ```swift
  public func scanSkills(
      at repositoryPath: URL,
      globalCommandsDirectory: URL? = defaultGlobalCommandsDirectory,
      globalSkillsDirectories: [URL] = defaultGlobalSkillsDirectories
  ) throws -> [SkillInfo]
  ```
  Use `[URL]` (not optional) — empty array disables it; matches how the project loop iterates `Self.skillsDirectories`.
- Extract the existing project-skills loop body into a private helper `scanSkillsDirectory(_ directory: URL, source: SkillSource, visited: inout Set<String>) -> [SkillInfo]` so the same code handles both project and user skill dirs.
- After project skills + project commands + global commands are appended, run the new helper for each entry in `globalSkillsDirectories` with `source: .user`.
- **Precedence fix**: before the final `seen.insert($0.name)` dedup, do a stable sort so project entries come first (e.g. partition into `[project, user]` and concatenate, then dedup). This guarantees a user-source skill is dropped when a project skill of the same name exists rather than depending on alphabetical accident.
- Make sure symlink resolution + the shared `visited` set still prevent double-walks if a user has `~/.claude/skills` symlinked to `~/.agents/skills`.

Files touched:
- `AIDevToolsKit/Sources/SDKs/SkillScannerSDK/SkillScanner.swift`

## - [x] Phase 2: Thread global skill dirs through `LoadSkillsUseCase`

**Skills used**: `ai-dev-tools-architecture`, `swift-architecture`
**Principles applied**: Added `globalSkillsDirectories: [URL]` parameter to `LoadSkillsUseCase.init` with a default of `SkillScanner.defaultGlobalSkillsDirectories`, so existing call sites compile unchanged and the Features layer stays free of any concrete path knowledge (it just forwards the SDK-supplied default). Captured both global parameters into locals before the detached task so the closure stays `Sendable` and doesn't capture `self`. Left `ScanSkillsUseCase` untouched — it already calls `scanner.scanSkills(at:)` with no overrides, so it inherits the new user-skills default automatically; no divergence comment needed.

**Skills to read**: `ai-dev-tools-architecture`, `swift-architecture`

- Update `LoadSkillsUseCase` (`Features/SkillBrowserFeature/LoadSkillsUseCase.swift`) to accept `globalSkillsDirectories: [URL]` with the default `SkillScanner.defaultGlobalSkillsDirectories`.
- Pass that array into `scanner.scanSkills(at:globalCommandsDirectory:globalSkillsDirectories:)` inside the detached task.
- Verify the `ScanSkillsUseCase` in `Features/ChatFeature/ScanSkillsUseCase.swift` either gets the same treatment or — if it intentionally scopes to project-only — leave it alone but add a one-line comment explaining the divergence.

Files touched:
- `AIDevToolsKit/Sources/Features/SkillBrowserFeature/LoadSkillsUseCase.swift`
- (review) `AIDevToolsKit/Sources/Features/ChatFeature/ScanSkillsUseCase.swift`

## - [x] Phase 3: Wire defaults through Mac app + CLI composition

**Skills used**: `ai-dev-tools-composition-root`
**Principles applied**: Verified that all `LoadSkillsUseCase()` call sites (Mac `AIDevToolsKitMacEntryView` and CLI `SkillsCommand`) construct the use case with no overrides, so they transparently inherit the new `SkillScanner.defaultGlobalSkillsDirectories` default from the SDK. The composition root pattern is preserved — defaults live in the SDK, the Features layer forwards them, and the Apps layer accepts them implicitly without baking any path knowledge into platform code. No platform-specific override is wired today; configurable global skill paths via `SettingsService`/`DataPathsService` are deferred as a follow-up pending Bill's confirmation.

**Skills to read**: `ai-dev-tools-composition-root`

- The default values bake the user paths into the SDK, so the Mac app and CLI work out of the box. Walk the call sites anyway:
  - `Apps/AIDevToolsKitMac/Models/WorkspaceModel.swift` — confirm `LoadSkillsUseCase()` is constructed with no overrides and picks up the new default.
  - `Apps/AIDevToolsKitCLI/SkillsCommand.swift` — same check.
- If either site overrides defaults today, plumb in the new parameter so it remains overridable from tests or composition roots.
- Decision check: do we want the global skill paths to be configurable via settings (the way other paths flow through `DataPathsService` / `SettingsService`)? For this pass, default-only is fine — note as a follow-up if Bill confirms he wants user override.

Files touched:
- (review) `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/WorkspaceModel.swift`
- (review) `AIDevToolsKit/Sources/Apps/AIDevToolsKitCLI/SkillsCommand.swift`

## - [x] Phase 4: Surface skill source in the Mac Skills sidebar

**Skills used**: `ai-dev-tools-code-quality`
**Principles applied**: Extracted the row into a `SkillRow` subview so the badge logic stays local and the row remains the single source of truth for the sidebar's visual treatment. Used the typed `SkillSource.user` case directly rather than re-encoding the source as a string, so the badge can never silently diverge from the model. Selection stays keyed by `skill.name` (current behavior); Phase 1 dedup guarantees name lookup remains unambiguous.

**Skills to read**: `ai-dev-tools-code-quality`

- In `Apps/AIDevToolsKitMac/Views/SkillsContainer.swift`, update the sidebar row to show a small trailing badge ("user") when `skill.source == .user`. Use a subtle secondary-colored capsule so project skills remain visually dominant.
- Keep selection keyed by `skill.name` (current behavior). Verify the dedup in Phase 1 means name-based lookup still works.
- Optional: group the list with section headers ("Project" / "User") if Bill prefers it over an inline badge — confirm before implementing. Default to the badge approach (lower visual disruption).

Files touched:
- `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Views/SkillsContainer.swift`

## - [x] Phase 5: Validation

**Skills used**: `ai-dev-tools-swift-testing`
**Principles applied**: Added four new `@Test` cases in `SkillScannerTests` for global discovery, project-over-user precedence, empty-array opt-out, and symlink dedup — each using sentence-form names and strict Arrange-Act-Assert separation. Discovered that existing tests were silently leaking Bill's real `~/.agents/skills` into the temp-repo cases (the new default scanned home), and fixed it by adding `globalSkillsDirectories: []` to every existing call — analogous to the existing `globalCommandsDirectory: nil` opt-out. CLI smoke (`swift run ai-dev-tools-kit skills <repo>`) confirms user-source skills like `grill-me`, `slack-message`, `text-me` appear with `(user)` suffix and project skills win on name collisions. Mac app smoke deferred to Bill (requires interactive UI launch); UI screenshot test skipped — no Skills sidebar screenshot test exists in the current suite to extend. No `ai-dev-tools-enforce` violations expected: changes are test-only plus four single-arg additions in existing call sites.

**Skills to read**: `ai-dev-tools-swift-testing`, `ai-dev-tools-ui-tests`, `ai-dev-tools-enforce`

- **Unit tests** in `SkillScannerSDK` tests:
  - With a temp repo containing `.agents/skills/foo/SKILL.md` and a temp global dir containing `bar/SKILL.md`, scan returns both with correct `source` values.
  - When a global skill and a project skill share a name, the project entry wins and the user entry is dropped.
  - Empty `globalSkillsDirectories` array produces no user-source skills.
  - Symlink case: a `claude/skills -> agents/skills` symlink at the global level doesn't duplicate entries.
- **CLI smoke**: run `swift run ai-dev-tools skills <repo-path>` against this repo and confirm Bill's `~/.agents/skills` entries appear with `(user)` suffix.
- **Mac app smoke**: launch the Mac app, open the Skills tab on this repo, confirm a user-source skill (e.g. `grill-me`) appears with the "user" badge and that selecting it renders the detail correctly via `SkillDetailView`.
- **UI test (optional)**: extend the existing Skills screenshot test (if present in `ai-dev-tools-ui-tests` skill scope) to capture the sidebar with at least one user-source row.
- **Enforce pass**: run the `ai-dev-tools-enforce` skill across every file touched in Phases 1–4 to catch architecture / build-quality / code-quality regressions before merging.
