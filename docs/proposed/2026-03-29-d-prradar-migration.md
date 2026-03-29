# PRRadar Migration to AIDevTools

**Date:** 2026-03-29
**Status:** Proposed

## Goal

Migrate the entire PRRadar project (`/Users/bill/Developer/personal/PRRadar`) into AIDevTools so that:

1. PRRadar's Mac app becomes a new **"PR Radar"** tab in the AIDevTools workspace (per-repo)
2. PRRadar's CLI commands are available through the AIDevTools CLI
3. All Swift targets land in the correct architecture layer (Apps, Features, Services, SDKs)
4. The project builds and works end-to-end, even if some redundancy remains initially
5. Deduplication of overlapping modules happens in later phases

## Guiding Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| GitHub API client | **Octokit** (PRRadar's `OctokitClient`) | Bill's preference; richer API coverage including GraphQL |
| Overlapping SDKs | **Use AIDevTools' versions** and extend with missing PRRadar functionality | AIDevTools' SDKs are generally supersets |
| Naming conflicts | **Prefix PRRadar-unique modules** with `PRRadar` where needed | Avoids confusion during transition |
| Build target strategy | **Targets in single Package.swift** | Matches AIDevTools' existing convention |
| Migration order | **Bottom-up** (SDKs → Services → Features → Apps) | Each phase produces a buildable state |
| Deduplication timing | **After** PRRadar builds in AIDevTools | Get it working first, then clean up |
| Repository management | **Single shared repo list** via `RepositoryInfo` + per-feature settings store | Follow established pattern (like `EvalRepoSettings`) |

## Repository & Settings Integration

### Principle: One Repo List, Supplementary Settings

AIDevTools already has a shared repo list (`RepositoryStore` → `[RepositoryInfo]`) displayed in the workspace sidebar. PRRadar plugs into this — it does **not** introduce its own concept of repos or configurations.

PRRadar-specific settings (rule paths, diff source) are supplementary per-repo config, stored in a per-feature settings store — the same pattern `EvalRepoSettings` and `MarkdownPlannerRepoSettings` already use.

### Config vs Artifacts (Don't Confuse These)

**Config** — user-set preferences that rarely change:
- Rule paths (where review rules live)
- Diff source (git vs GitHub API)

**Artifacts** — runtime output from running PRRadar analysis:
- Diffs, evaluations, reports, comments
- Stored under `DataPathsService` like other feature output
- Path: `{dataPathsRoot}/prradar/{repoName}/{prNumber}/`

These are completely separate concerns. Config goes in a settings store. Artifacts go in data paths.

### Config: PRRadarRepoSettings

Follows the established `EvalRepoSettingsStore` pattern:

```swift
// Sources/Services/PRRadarConfigService/PRRadarRepoSettings.swift
public struct PRRadarRepoSettings: Codable, Sendable {
    public let repoId: UUID
    public var rulePaths: [RulePath]       // Rule set locations
    public var diffSource: DiffSource      // .git or .githubAPI
}
```

Stored at `ServicePath.prradarSettings` → `{dataPathsRoot}/prradar/settings/prradar-settings.json`

### Artifacts: DataPathsService

Add a new `ServicePath` case for PRRadar output:

```swift
case prradarSettings           // prradar/settings
case prradarOutput(String)     // prradar/repos/{repoName}
```

PRRadar's existing phase output code writes to this path instead of a user-configured `outputDir`.

### Field Mapping (PRRadar → AIDevTools)

| PRRadar Field | Where It Goes | Notes |
|---------------|--------------|-------|
| `name` | `RepositoryInfo.name` | Already exists |
| `repoPath` | `RepositoryInfo.path` | Already exists |
| `githubAccount` | `RepositoryInfo.credentialAccount` | Already exists |
| `defaultBaseBranch` | `RepositoryInfo.pullRequest.baseBranch` | Already exists |
| `isDefault` | **Dropped** | AIDevTools uses runtime selection |
| `rulePaths` | `PRRadarRepoSettings.rulePaths` | Per-feature settings store |
| `diffSource` | `PRRadarRepoSettings.diffSource` | Per-feature settings store |
| `outputDir` | `DataPathsService.path(for: .prradarOutput(repoName))` | Derived from data paths, not config |
| `agentScriptPath` | Derived at runtime | Not stored |

### Settings UI

PRRadar config appears as a section in the existing repo edit form — same place evals and plans already have their settings. No separate settings scene.

### Credentials

Both projects use the same `KeychainSDK` with account-based lookup. A repo's `credentialAccount` on `RepositoryInfo` works for all features — PRRadar, evals, chains, etc.

## Overlap Analysis

### SDKs — AIDevTools Is Superset (Reuse AIDevTools')

| Module | AIDevTools | PRRadar | Gap to Close |
|--------|-----------|---------|--------------|
| **GitSDK** | 3 files, worktree/branch/commit ops | 2 files, basic ops + `GitOperationsService` | Add missing methods from `GitOperationsService` to `GitClient` (`isGitRepository`, `getFileContent`, `getRepoRoot`, `getMergeBase`, `getRemoteURL`, `getBlobHash`, `diffNoIndex`, `clean`, `checkWorkingDirectoryClean`) |
| **KeychainSDK** | 5 credential types | 2 credential types | No gap — superset |
| **EnvironmentSDK** | 3 files (incl. PythonEnvironment) | 2 files | No gap — superset |
| **ConcurrencySDK** | `InactivityWatchdog` + `timeSinceLastActivity()` | `InactivityWatchdog` | No gap — superset |
| **LoggingSDK** | 3 files, basic reader | 3 files, reader + run tracking | Add `readLastRun()` and `readRuns()` to AIDevTools' `LogReaderService`; parameterize app name in bootstrap |

### SDKs — PRRadar-Unique (Must Bring Over)

| Module | What It Does | New Name in AIDevTools |
|--------|-------------|----------------------|
| **GitHubSDK** | Octokit wrapper (`OctokitClient`, `ImageDownloadService`) | **OctokitSDK** (to distinguish from `gh` CLI approach) |
| **ClaudeSDK** | Python Claude Agent bridge (`ClaudeAgentClient`) | **ClaudeAgentSDK** (to distinguish from `ClaudeCLISDK` and `ClaudePythonSDK`) |

### Services — All Unique to PRRadar (Must Bring Over)

| Module | Dependencies | Notes |
|--------|-------------|-------|
| **PRRadarModels** | Foundation only (+ swift-crypto conditional) | Domain models for diffs, rules, evaluations |
| **PRRadarConfigService** | PRRadarModels, KeychainSDK, EnvironmentSDK | Configuration, paths, credentials |
| **PRRadarCLIService** | ClaudeAgentSDK, GitSDK, OctokitSDK, PRRadarConfigService, PRRadarModels, EnvironmentSDK | Core business logic |

### Features — Unique to PRRadar

| Module | Dependencies |
|--------|-------------|
| **PRReviewFeature** | PRRadarCLIService, PRRadarConfigService, PRRadarModels, LoggingSDK |

### Apps — Integration Points

| PRRadar Module | Integration Target |
|---------------|-------------------|
| **MacApp** (views + models) | New tab in `AIDevToolsKitMac` `WorkspaceView` |
| **PRRadarMacCLI** (15+ commands) | New command group in `AIDevToolsKitCLI` |

## External Dependencies to Add

```swift
.package(url: "https://github.com/nerdishbynature/octokit.swift", from: "0.14.0"),
.package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "main"),
// swift-crypto only needed on non-Apple platforms (conditional)
```

Note: `swift-argument-parser`, `swift-log`, `SwiftCLI`, `swift-markdown-ui` are already present.

---

## Phase Plan

### Phase 1: Add External Dependencies & New Unique SDKs

**Goal:** Get the foundation layer building.

**Steps:**

1. Add `octokit.swift` and `swift-markdown` package dependencies to `Package.swift`
2. Add conditional `swift-crypto` dependency
3. Copy PRRadar's `GitHubSDK` → `AIDevToolsKit/Sources/SDKs/OctokitSDK/`
   - Rename module references from `GitHubSDK` to `OctokitSDK`
   - Add target to `Package.swift` with `OctoKit` dependency
4. Copy PRRadar's `ClaudeSDK` → `AIDevToolsKit/Sources/SDKs/ClaudeAgentSDK/`
   - Rename module from `ClaudeSDK` to `ClaudeAgentSDK`
   - Update imports: `ConcurrencySDK` and `EnvironmentSDK` (already exist in AIDevTools)
   - Remove duplicated `PythonEnvironment.swift` (use `EnvironmentSDK`'s version)
   - Add target to `Package.swift`

**Verification:** `swift build --target OctokitSDK` and `swift build --target ClaudeAgentSDK` succeed.

### Phase 2: Extend Overlapping SDKs

**Goal:** AIDevTools' shared SDKs cover all functionality PRRadar needs.

**Steps:**

1. **GitSDK** — Add to `GitClient.swift`:
   - `isGitRepository(at:)` → runs `git rev-parse --is-inside-work-tree`
   - `getFileContent(ref:path:)` → runs `git show ref:path`
   - `getRepoRoot()` → runs `git rev-parse --show-toplevel`
   - `getMergeBase(ref1:ref2:)` → runs `git merge-base`
   - `getRemoteURL(name:)` → runs `git remote get-url`
   - `getBlobHash(ref:path:)` → runs `git rev-parse ref:path`
   - `diffNoIndex(path1:path2:)` → runs `git diff --no-index`
   - `clean(force:directories:)` → runs `git clean`
   - `isWorkingDirectoryClean()` → runs `git status --porcelain`
   - Add corresponding CLI definitions to `GitCLI.swift`

2. **LoggingSDK** — Add to `LogReaderService.swift`:
   - `readLastRun(marker:)` → reads log entries from last occurrence of marker to end
   - `readRuns(marker:)` → splits log into logical runs separated by marker
   - Parameterize `AIDevToolsLogging.bootstrap()` to accept an app name (default "AIDevTools", PRRadar passes "PRRadar")

**Verification:** All existing tests still pass; new methods compile.

### Phase 3: Migrate Services Layer

**Goal:** All PRRadar domain models and services build in AIDevTools.

**Steps:**

1. Copy `PRRadarModels` → `AIDevToolsKit/Sources/Services/PRRadarModels/`
   - Add target with conditional swift-crypto dependency
   - No import changes needed (Foundation-only)

2. Copy `PRRadarConfigService` → `AIDevToolsKit/Sources/Services/PRRadarConfigService/`
   - Verify imports of `KeychainSDK` and `EnvironmentSDK` resolve to AIDevTools' versions
   - **Drop** `SettingsService`, `AppSettings`, `RepositoryConfigurationJSON` — repos come from shared `RepositoryStore`
   - **Add** `PRRadarRepoSettings` + `PRRadarRepoSettingsStore` (follows `EvalRepoSettingsStore` pattern) for rule paths and diff source
   - **Keep** `RepositoryConfiguration` as a runtime-assembled object — factory builds it from `RepositoryInfo` + `PRRadarRepoSettings` + `DataPathsService` (for artifact output path)
   - Keep credential resolution, path utilities, and other non-settings config code
   - Add target to `Package.swift` with `RepositorySDK` and `DataPathsService` as dependencies

3. Copy `PRRadarCLIService` → `AIDevToolsKit/Sources/Services/PRRadarCLIService/`
   - Update `import GitHubSDK` → `import OctokitSDK`
   - Update `import ClaudeSDK` → `import ClaudeAgentSDK`
   - Verify `GitSDK` imports work (PRRadar uses `GitOperationsService`; need adapter or update call sites to use `GitClient`)
   - Add target to `Package.swift`

**Key decision for PRRadarCLIService + GitSDK:** PRRadar's code calls `GitOperationsService` methods. Two options:
- **Option A:** Add a `GitOperationsService` typealias/wrapper in GitSDK that delegates to `GitClient` (quick, deferred cleanup)
- **Option B:** Update all call sites in `PRRadarCLIService` to use `GitClient` directly (cleaner but more changes)

**Recommendation:** Option A for this phase (get it building), Option B in deduplication.

**Verification:** `swift build --target PRRadarCLIService` succeeds.

### Phase 4: Migrate Feature Layer

**Goal:** PRReviewFeature builds in AIDevTools.

**Steps:**

1. Copy `PRReviewFeature` → `AIDevToolsKit/Sources/Features/PRReviewFeature/`
2. Update imports (`ClaudeSDK` → `ClaudeAgentSDK`, `GitHubSDK` → `OctokitSDK`)
3. Add target to `Package.swift` with dependencies on PRRadarCLIService, PRRadarConfigService, PRRadarModels, LoggingSDK

**Verification:** `swift build --target PRReviewFeature` succeeds.

### Phase 5: Migrate Mac App Views as New Tab

**Goal:** PRRadar UI appears as a new tab in the AIDevTools workspace.

**Steps:**

1. Copy PRRadar `MacApp/` → `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/PRRadar/`
   - All models: `AppModel`, `AllPRsModel`, `PRModel`, `SettingsModel`
   - All views: `ContentView` (rename to `PRRadarContentView`), phase views, git views, utilities
2. Update imports across all copied files
3. Rename PRRadar's `ContentView` → `PRRadarContentView` to avoid collision
4. Adapt PRRadar's models to work within AIDevTools' `CompositionRoot`:
   - **Remove** PRRadar's `AppModel` and `SettingsModel` — repo selection and settings are handled by `WorkspaceModel`
   - **Keep** `AllPRsModel` and `PRModel` — they operate on PRRadar domain types (diffs, evaluations, reports), not repo config
   - `PRRadarContentView` receives the selected `RepositoryInfo` from the workspace and builds a `RepositoryConfiguration` from `RepositoryInfo` + `PRRadarRepoSettings` + `DataPathsService`
   - Credentials already shared via `KeychainSDK` + `credentialAccount`
5. Add PRRadar settings as a section in the repo edit form (rule paths, diff source)
6. Add `PRRadarContentView` as a new tab in `WorkspaceView`:
   ```swift
   PRRadarContentView(repository: repo)
       .tabItem { Label("PR Radar", systemImage: "eye") }
       .tag("prradar")
   ```
6. Add `PRReviewFeature`, `PRRadarCLIService`, `PRRadarConfigService`, `PRRadarModels`, `OctokitSDK` to `AIDevToolsKitMac` target dependencies
7. Add `MarkdownUI` and `Markdown` dependencies (already available)

**Verification:** Mac app builds, new tab appears, PR list loads for a configured repo.

### Phase 6: Migrate CLI Commands

**Goal:** PRRadar CLI commands available through `ai-dev-tools-kit`.

**Steps:**

1. Copy PRRadar CLI commands → `AIDevToolsKit/Sources/Apps/AIDevToolsKitCLI/PRRadar/`
2. Create a `PRRadarCommand` group that nests all subcommands
3. Register `PRRadarCommand` as a subcommand of the main CLI
4. Update imports in all command files
5. Add feature/service/SDK dependencies to `AIDevToolsKitCLI` target

**Verification:** `swift build --target ai-dev-tools-kit` succeeds; `ai-dev-tools-kit prradar --help` lists subcommands.

### Phase 7: Migrate Tests

**Goal:** All PRRadar tests pass in AIDevTools.

**Steps:**

1. Copy test targets:
   - `LoggingSDKTests` → merge into existing (or add new test cases)
   - `PRRadarModelsTests` → `Tests/Services/PRRadarModelsTests/` (with fixture data)
   - `MacAppTests` → `Tests/Apps/PRRadarMacAppTests/`
2. Add test targets to `Package.swift`
3. Update imports in test files
4. Verify fixture data paths resolve correctly

**Verification:** `swift test` passes for all new and existing test targets.

### Phase 7b: End-to-End CLI Verification Against PRRadar-TestRepo

**Goal:** Prove the migrated CLI works by running real analysis against `gestrich/PRRadar-TestRepo`.

This is not an automated integration test — it's a manual verification step where you run CLI commands and confirm output. The test repo has open PRs specifically for this purpose (e.g., PR #23 "Test: Validator with violations", PR #24 "Test: grouped import order violations").

**Setup:**
- Test repo: `/Users/bill/Developer/personal/PRRadar-TestRepo` (remote: `gestrich/PRRadar-TestRepo`)
- The repo must be registered in AIDevTools' shared repo list with PRRadar settings configured (rule paths pointing to the test repo's `rules/` directory)

**Verification commands** (using the migrated `ai-dev-tools-kit prradar` CLI):

1. **Refresh PR list** — confirm GitHub API (Octokit) works:
   ```
   ai-dev-tools-kit prradar refresh --config PRRadar-TestRepo
   ```

2. **Dry-run analysis on a test PR** — confirm diff fetching, rule loading, and analysis pipeline work:
   ```
   ai-dev-tools-kit prradar run 23 --config PRRadar-TestRepo --mode regex --quiet
   ```

3. **Post comments to a test PR** — confirm comment posting works end-to-end:
   ```
   ai-dev-tools-kit prradar run 23 --config PRRadar-TestRepo --mode regex --no-dry-run
   ```

4. **Verify output artifacts** — confirm artifacts land in `DataPathsService` path:
   ```
   ls ~/Desktop/ai-dev-tools/prradar/repos/PRRadar-TestRepo/23/
   ```

**Success criteria:**
- PR list refreshes and shows open PRs
- Regex-mode analysis completes without errors and produces report artifacts
- Comments are posted to the test PR on GitHub
- Artifacts are written to the correct `DataPathsService`-managed path (not a separate output directory)

---

### Phase 8: Migrate Skills, Scripts, Docs, and Remaining Assets

**Goal:** Nothing left behind in the old repo. Every useful asset lives in AIDevTools.

**Skills** (`.claude/skills/` → `.agents/skills/`):
- `pr-radar-add-rule/SKILL.md` — create new review rules
- `pr-radar-debug/SKILL.md` — debugging guide
- `pr-radar-todo/SKILL.md` — TODO management
- `pr-radar-verify-work/SKILL.md` — verify changes against test repo

**Scripts** (`scripts/`):
- `daily-review.sh` — cron/launchd daily PR review runner
- `run-pr-radar.sh` — trigger GitHub Actions workflow for a PR

**Python Agent Bridge** (`PRRadarLibrary/claude-agent/`):
- `claude_agent.py` — Python wrapper for Claude Agent SDK (stdin JSON → stdout JSON-line)
- `requirements.txt` — Python deps (`claude-agent-sdk`)
- Do NOT migrate `.venv/` — regenerate from requirements.txt

**Documentation** (`docs/`):
- `docs/completed/` — 21 completed feature docs → merge into AIDevTools `docs/completed/`
- `docs/proposed/` — 16+ proposals + TODO + roadmap → merge into AIDevTools `docs/proposed/`
- `docs/rule-examples/` — example review rules → `docs/rule-examples/`
- `docs/plugin/` — plugin docs (SKILL.md, roadmap, guides)
- `ci-setup.md` — CI/CD instructions
- Root `README.md` content → fold into AIDevTools README or a `docs/prradar.md`

**Claude Code Config** (`.claude/`):
- `CLAUDE.md` — merge PRRadar-specific instructions into AIDevTools' `CLAUDE.md`
- `settings.json` / `settings.local.json` — merge allowed commands
- `xcuitest-notes.md` — keep as reference
- `.xcuitest-config.json` — adapt for new project structure

**App Assets:**
- `PRRadar/Assets.xcassets/AppIcon.appiconset/pr-radar-gemini.png` — the PR Radar icon (green neon code radar). Add to AIDevTools asset catalog and use as the PR Radar tab icon in the workspace
- `PRRadar/Assets.xcassets/AccentColor.colorset/` — accent color definition
- `PRRadarMac.entitlements` — merge needed entitlements into AIDevTools app

**XCUITests:**
- `PRRadarMacUITests/` → `Tests/Apps/PRRadarMacUITests/` (adapt for new tab-based structure)

**IDE Config:**
- `.vscode/launch.json` — 6 debug configs → adapt paths and merge into AIDevTools' launch.json

**NOT migrated** (generated/personal):
- `.venv/` — regenerate
- `xcuserdata/` — regenerate
- `.env` — sensitive, per-machine
- `.build/`, `SourcePackages/` — generated
- `PRRadar.xcodeproj/` — the Xcode project wrapper is replaced by AIDevTools' project
- `Package.resolved` — regenerated by the new package

**Verification:** `git status` on old PRRadar repo shows nothing unaccounted for. All useful content has a home in AIDevTools.

---

## Future Deduplication Phases (Post-Migration)

These are tracked separately and happen after PRRadar is fully building:

### Phase 9: Unify Git Operations
- Remove `GitOperationsService` wrapper
- Update all PRRadarCLIService call sites to use `GitClient` directly
- Consolidate any remaining git-related utilities

### Phase 10: Unify GitHub Clients
- Evaluate whether `gh` CLI usage in `ClaudeChainSDK` should migrate to `OctokitSDK`
- Or keep both: Octokit for rich API needs, `gh` CLI for simple CI operations
- Define a shared `GitHubClientProtocol` if both are retained

### Phase 11: Simplify PRRadar Configuration
- Evaluate whether `RepositoryConfiguration` runtime object can be removed entirely
- PRRadar code could take `RepositoryInfo` + `PRRadarRepoSettings` directly
- Remove any remaining adapter shims from Phase 3

### Phase 13: Migrate PRRadar to AIOutputSDK Provider Framework
- PRRadar currently uses `ClaudeAgentSDK` (Python bridge) — tightly coupled to one AI provider
- AIDevTools has `AIOutputSDK` — a provider-agnostic framework with `AIClient` protocol and multiple implementations (Anthropic API, Claude CLI, Codex CLI)
- Migrate PRRadar's `AnalysisService` to use `AIClient` instead of `ClaudeAgentClient` directly
- This unlocks provider selection in the PR Radar tab (same picker used by evals and chat)
- `ClaudeAgentSDK` could become another `AIClient` implementation, or be retired if the Anthropic SDK provider covers the same use cases
- Structured output (`runStructured<T>`) may replace PRRadar's custom JSON schema passing

---

## Dependency Graph After Migration (Phase 1-8 Complete)

```
Apps Layer:
  AIDevToolsKitMac ──→ PRReviewFeature, PRRadarCLIService, PRRadarConfigService,
                        PRRadarModels, OctokitSDK (+ all existing deps)
  AIDevToolsKitCLI ──→ PRReviewFeature, PRRadarCLIService, PRRadarConfigService,
                        PRRadarModels, OctokitSDK (+ all existing deps)

Features Layer:
  PRReviewFeature ──→ PRRadarCLIService, PRRadarConfigService, PRRadarModels, LoggingSDK

Services Layer:
  PRRadarCLIService ──→ ClaudeAgentSDK, GitSDK, OctokitSDK, PRRadarConfigService,
                         PRRadarModels, EnvironmentSDK
  PRRadarConfigService ──→ PRRadarModels, KeychainSDK, EnvironmentSDK
  PRRadarModels ──→ (Foundation only)

SDKs Layer:
  OctokitSDK ──→ OctoKit (external)
  ClaudeAgentSDK ──→ CLISDK, ConcurrencySDK, EnvironmentSDK
  (all existing SDKs unchanged)
```

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Import name collisions (e.g., both projects define `GitCLI`) | PRRadar's `GitCLI` is replaced by AIDevTools' version; PRRadar's `GitOperationsService` becomes a thin wrapper |
| PRRadar's `ContentView` name conflict | Rename to `PRRadarContentView` |
| Credential flow differences | Keep both flows initially; unify in Phase 11 |
| `OctoKit` type collisions with internal types | PRRadar already namespaces via `OctokitClient` wrapper |
| Large PR size | Each phase is a separate PR; phases 1-4 are mechanical copies |

## Execution Notes

- Each phase should be a **separate PR** for reviewability
- Run `swift build` after each phase to verify incremental progress
- The Mac app Xcode project (`AIDevTools.xcodeproj`) may need scheme updates after Phase 5
- PRRadar's Xcode project (`PRRadar.xcodeproj`) is **not** migrated — only the Swift package contents
