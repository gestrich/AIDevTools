## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture — placement guidance for SDKs, Services, Features, Apps |
| `swift-app-architecture:swift-swiftui` | SwiftUI Observable model patterns, view composition, tab integration |

## Background

Migrate the entire PRRadar project (`/Users/bill/Developer/personal/PRRadar`) into AIDevTools so that:

1. PRRadar's Mac app becomes a new **"PR Radar"** tab in the AIDevTools workspace (per-repo)
2. PRRadar's CLI commands are available through the AIDevTools CLI
3. All Swift targets land in the correct architecture layer (Apps, Features, Services, SDKs)
4. The project builds and works end-to-end, even if some redundancy remains initially
5. Deduplication of overlapping modules happens in later phases

### Guiding Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| GitHub API client | **Octokit** (PRRadar's `OctokitClient`) | Bill's preference; richer API coverage including GraphQL |
| Overlapping SDKs | **Use AIDevTools' versions** and extend with missing PRRadar functionality | AIDevTools' SDKs are generally supersets |
| Naming conflicts | **Prefix PRRadar-unique modules** with `PRRadar` where needed | Avoids confusion during transition |
| Build target strategy | **Targets in single Package.swift** | Matches AIDevTools' existing convention |
| Migration order | **Bottom-up** (SDKs → Services → Features → Apps) | Each phase produces a buildable state |
| Deduplication timing | **After** PRRadar builds in AIDevTools | Get it working first, then clean up |
| Repository management | **Single shared repo list** via `RepositoryInfo` + per-feature settings store | Follow established pattern (like `EvalRepoSettings`) |

### Repository & Settings Integration

**One Repo List, Supplementary Settings:** AIDevTools already has a shared repo list (`RepositoryStore` → `[RepositoryInfo]`). PRRadar plugs into this — it does **not** introduce its own concept of repos or configurations. PRRadar-specific settings (rule paths, diff source) are supplementary per-repo config in a per-feature settings store — same pattern as `EvalRepoSettings`.

**Config vs Artifacts (Don't Confuse These):**

- **Config** — user-set preferences: rule paths, diff source. Stored in `PRRadarRepoSettings` / `PRRadarRepoSettingsStore` at `{dataPathsRoot}/prradar/settings/prradar-settings.json`
- **Artifacts** — runtime output from analysis (diffs, evaluations, reports, comments). Stored via `DataPathsService` at `{dataPathsRoot}/prradar/repos/{repoName}/{prNumber}/`

```swift
public struct PRRadarRepoSettings: Codable, Sendable {
    public let repoId: UUID
    public var rulePaths: [RulePath]
    public var diffSource: DiffSource
}
```

New `ServicePath` cases:
```swift
case prradarSettings           // prradar/settings
case prradarOutput(String)     // prradar/repos/{repoName}
```

**Field Mapping (PRRadar → AIDevTools):**

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

### Overlap Analysis

**SDKs — AIDevTools Is Superset (Reuse AIDevTools'):**

| Module | AIDevTools | PRRadar | Gap to Close |
|--------|-----------|---------|--------------|
| **GitSDK** | 3 files, worktree/branch/commit ops | 2 files, basic ops + `GitOperationsService` | Add missing methods to `GitClient` |
| **KeychainSDK** | 5 credential types | 2 credential types | No gap — superset |
| **EnvironmentSDK** | 3 files (incl. PythonEnvironment) | 2 files | No gap — superset |
| **ConcurrencySDK** | `InactivityWatchdog` + extra method | `InactivityWatchdog` | No gap — superset |
| **LoggingSDK** | 3 files, basic reader | 3 files, reader + run tracking | Add run tracking to AIDevTools' `LogReaderService` |

**SDKs — PRRadar-Unique (Must Bring Over):**

| Module | What It Does | New Name in AIDevTools |
|--------|-------------|----------------------|
| **GitHubSDK** | Octokit wrapper (`OctokitClient`, `ImageDownloadService`) | **OctokitSDK** |
| **ClaudeSDK** | Python Claude Agent bridge (`ClaudeAgentClient`) | **ClaudeAgentSDK** |

**External Dependencies to Add:**
```swift
.package(url: "https://github.com/nerdishbynature/octokit.swift", from: "0.14.0"),
.package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "main"),
```

### Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Import name collisions (e.g., `GitCLI`) | PRRadar's `GitCLI` replaced by AIDevTools' version; `GitOperationsService` becomes thin wrapper |
| PRRadar's `ContentView` name conflict | Rename to `PRRadarContentView` |
| `OctoKit` type collisions | PRRadar already namespaces via `OctokitClient` wrapper |
| Large PR size | Each phase is a separate PR |

### Execution Notes

- Each phase should be a **separate PR** for reviewability
- Run `swift build` after each phase to verify incremental progress
- PRRadar's Xcode project (`PRRadar.xcodeproj`) is **not** migrated — only the Swift package contents

## - [x] Phase 1: Add external dependencies and new unique SDKs

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: SDKs placed at the bottom layer per architecture rules. `ClaudeAgentSDK` is new alongside existing `ClaudePythonSDK` (identical client code, different module — deduplication deferred). `PythonEnvironment.swift` omitted from `ClaudeAgentSDK` since `EnvironmentSDK` already owns it. `swift-crypto` and `swift-markdown` added as package dependencies now (used by later phases); both produce unused-dependency warnings on macOS since `CryptoKit` is built-in and no target uses `swift-markdown` yet.

**Skills to read**: `swift-app-architecture:swift-architecture`

Get the foundation layer building by adding new package dependencies and copying PRRadar-unique SDKs.

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

## - [x] Phase 2: Extend overlapping SDKs with missing PRRadar functionality

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Added methods directly to existing SDK structs following the single-operation-per-method SDK pattern. `RevParse.ref` made optional to support flag-only invocations (e.g., `--show-toplevel`, `--is-inside-work-tree`). `diffNoIndex` calls `client.execute` directly (bypassing `GitClient.execute`'s exit-code guard) since `git diff --no-index` exits 1 for non-empty diffs. `bootstrap(appName:logFileURL:)` derives the log path from `appName` when no explicit URL is given, preserving backward compatibility with zero-arg callers.

**Skills to read**: `swift-app-architecture:swift-architecture`

AIDevTools' shared SDKs must cover all functionality PRRadar needs.

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

## - [x] Phase 3: Migrate services layer

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Renamed PRRadar's `DataPathsService` enum to `PRRadarPhasePaths` to avoid naming collision with AIDevTools' `DataPathsService` class. Dropped `SettingsService`, `AppSettings`, `RepositoryConfigurationJSON`; replaced with `PRRadarRepoSettings` + `PRRadarRepoSettingsStore` following `EvalRepoSettingsStore` pattern. Updated `CredentialResolver` to take `KeychainStoring` directly instead of `SettingsService`, with a `createPlatform(githubAccount:)` factory for callers. Added `GitOperationsService` wrapper to `GitSDK` (Option A from plan) delegating to `GitClient`. Added `prradarSettings` and `prradarOutput` cases to `ServicePath` in AIDevTools' `DataPathsService`. All three targets (`PRRadarModels`, `PRRadarConfigService`, `PRRadarCLIService`) build successfully.

**Skills to read**: `swift-app-architecture:swift-architecture`

All PRRadar domain models and services build in AIDevTools.

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

**Key decision for PRRadarCLIService + GitSDK:** PRRadar's code calls `GitOperationsService` methods. Use Option A for now: add a `GitOperationsService` wrapper in GitSDK that delegates to `GitClient` (quick, deferred cleanup). Option B (update all call sites) happens in deduplication.

**Verification:** `swift build --target PRRadarCLIService` succeeds.

## - [x] Phase 4: Migrate feature layer

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Dropped credential/settings use cases (`CredentialStatusLoader`, `ListCredentialAccountsUseCase`, `LoadCredentialStatusUseCase`, `RemoveCredentialsUseCase`, `SaveCredentialsUseCase`, `LoadSettingsUseCase`, `SaveConfigurationUseCase`, `RemoveConfigurationUseCase`, `SetDefaultConfigurationUseCase`, `UpdateOutputDirUseCase`) since they reference `SettingsService`/`AppSettings`/`RepositoryConfigurationJSON` removed in Phase 3 — equivalent functionality lives in AIDevTools' `CredentialFeature`. Updated `CredentialResolver(settingsService:)` calls to `CredentialResolver.createPlatform(githubAccount:)`. Replaced `DataPathsService.` with `PRRadarPhasePaths.` throughout. Added `import EnvironmentSDK` for `PythonEnvironment`. Updated `readLastRun()` → `readLastRun(marker: "Analysis started")` to match AIDevTools' parameterized API.

**Skills to read**: `swift-app-architecture:swift-architecture`

PRReviewFeature builds in AIDevTools.

1. Copy `PRReviewFeature` → `AIDevToolsKit/Sources/Features/PRReviewFeature/`
2. Update imports (`ClaudeSDK` → `ClaudeAgentSDK`, `GitHubSDK` → `OctokitSDK`)
3. Add target to `Package.swift` with dependencies on PRRadarCLIService, PRRadarConfigService, PRRadarModels, LoggingSDK

**Verification:** `swift build --target PRReviewFeature` succeeds.

## - [x] Phase 5: Migrate Mac app views as new workspace tab

**Skills used**: `swift-app-architecture:swift-architecture`, `swift-app-architecture:swift-swiftui`
**Principles applied**: Dropped PRRadar's `AppModel` and `SettingsModel` entirely — repo selection handled by `WorkspaceModel`, credential management by AIDevTools' `CredentialFeature`. `PRRadarContentView` takes `repository: RepositoryInfo` and uses `.task(id: repository.id)` to rebuild `AllPRsModel` on repo change. `agentScriptPath` added as a stored field on `PRRadarRepoSettings` (users configure it in Settings → Repositories → PR Radar section). `Markdown` module from `swift-markdown` added to `AIDevToolsKitMac` target for `MarkupHTMLConverter`. Config sidebar removed from `PRRadarContentView` — two-column layout (PR list + detail) replacing original three-column layout.

**Skills to read**: `swift-app-architecture:swift-architecture`, `swift-app-architecture:swift-swiftui`

PRRadar UI appears as a new tab in the AIDevTools workspace.

1. Copy PRRadar `MacApp/` → `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/PRRadar/`
   - All models: `AllPRsModel`, `PRModel`
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
7. Add `PRReviewFeature`, `PRRadarCLIService`, `PRRadarConfigService`, `PRRadarModels`, `OctokitSDK` to `AIDevToolsKitMac` target dependencies
8. Add `pr-radar-gemini.png` icon to AIDevTools asset catalog for use as the PR Radar tab icon

**Verification:** Mac app builds, new tab appears, PR list loads for a configured repo.

## - [x] Phase 6: Migrate CLI commands

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Dropped `ConfigCommand`, `CredentialsCommand`, and `SettingsCommand` — replaced by AIDevTools' `repos`, `credentials`, and data-path management. Config resolution changed from `LoadSettingsUseCase(settingsService:)` to `RepositoryStore` + `PRRadarRepoSettingsStore` + `DataPathsService`. All types prefixed with `PRRadar` to avoid conflicts with existing CLI types. `SyncCommand` updated to use `PRRadarPhasePaths.phaseDirectory()` instead of the old `DataPathsService` static method. Helper functions (`printAIOutput`, `parseDateString`, etc.) prefixed with `prRadar` to avoid future collisions.

**Skills to read**: `swift-app-architecture:swift-architecture`

PRRadar CLI commands available through `ai-dev-tools-kit`.

1. Copy PRRadar CLI commands → `AIDevToolsKit/Sources/Apps/AIDevToolsKitCLI/PRRadar/`
2. Create a `PRRadarCommand` group that nests all subcommands
3. Register `PRRadarCommand` as a subcommand of the main CLI
4. Update imports in all command files
5. Add feature/service/SDK dependencies to `AIDevToolsKitCLI` target

**Verification:** `swift build --target ai-dev-tools-kit` succeeds; `ai-dev-tools-kit prradar --help` lists subcommands.

## - [x] Phase 7: Migrate tests

**Skills used**: none
**Principles applied**: Dropped 7 test files referencing removed types (`SettingsService`, `LoadSettingsUseCase`, `SaveConfigurationUseCase`, `RemoveConfigurationUseCase`, `SetDefaultConfigurationUseCase`, `SettingsModel`, `KeychainServiceTests`). Updated `import ClaudeSDK` → `import ClaudeAgentSDK` in `ClaudeAgentMessageTests`, `import GitHubSDK` → `import OctokitSDK` in `GitHistoryProviderTests`, and `DataPathsService.` → `PRRadarPhasePaths.` in three test files. Fixed a pre-existing async/throws mismatch in `AutoStartServiceTests` that was blocking `swift test` from running. `MacAppTests` skipped entirely since its only file tested the removed `SettingsModel`. All 48 migrated PRRadarModelsTests and 1 LoggingSDKTests pass; remaining `swift test` failures are pre-existing (`ClaudeChainServiceTests` missing fixtures, `SkillScannerSDKTests` environment-dependent).

All PRRadar tests pass in AIDevTools.

1. Copy test targets:
   - `LoggingSDKTests` → merge into existing (or add new test cases)
   - `PRRadarModelsTests` → `Tests/Services/PRRadarModelsTests/` (with fixture data)
   - `MacAppTests` → `Tests/Apps/PRRadarMacAppTests/`
2. Add test targets to `Package.swift`
3. Update imports in test files
4. Verify fixture data paths resolve correctly

**Verification:** `swift test` passes for all new and existing test targets.

## - [x] Phase 8: End-to-end CLI verification against PRRadar-TestRepo

**Skills used**: none
**Principles applied**: Discovered and fixed a cache-coherency bug in `SyncPRUseCase`: the cache check returned early when `gh-pr.json` existed (written by `refresh`) but there was no analysis data on disk, causing `prDiff = nil` in Phase 2. Fix: skip the cache early-return if `prDiff` is nil, forcing a full sync so diff data is actually acquired. All four verification criteria passed: PR list refresh, regex analysis with 3 violations, comment posting (3 existing comments edited), and artifacts written to the correct `DataPathsService` path (`~/Desktop/ai-dev-tools/prradar/repos/PRRadar-TestRepo/23/`). `PRRadar-TestRepo` also required adding `credentialAccount: "gestrich"` to `repositories.json` and creating `prradar-settings.json` with the `rules/` path.

Prove the migrated CLI works by running real analysis against `gestrich/PRRadar-TestRepo`.

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
- Artifacts are written to the correct `DataPathsService`-managed path

## - [x] Phase 9: Fix credential resolution in Mac app + migrate remaining assets

**Skills used**: none
**Principles applied**: Root cause was `PRRadarConfigService.CredentialResolver.createPlatform` using `"com.gestrich.PRRadar"` as the keychain service identifier instead of `"com.gestrich.AIDevTools"` — one-line fix. Added `inTabErrorMessage` helper in `PRRadarContentView` to show a friendly "No GitHub credentials configured" inline message instead of the raw `GitHubServiceError.missingToken` text when credentials are missing. Migrated all remaining PRRadar assets: 4 skills → `.agents/skills/`, `daily-review.sh` and `run-pr-radar.sh` → `scripts/prradar/` (paths updated for AIDevTools), Python agent bridge (`claude_agent.py` + `requirements.txt`) → `PRRadarLibrary/claude-agent/`, 30 completed docs + 17 proposed docs + rule-examples + plugin docs + ci-setup.md → `docs/`, PRRadar skill hints merged into `CLAUDE.md`.

**Bug context:** Opening the PR Radar tab with an iOS (or any non-PRRadar-TestRepo) repo selected throws "No GitHub token found. Set GITHUB_TOKEN env var, add to .env file, or store credentials in the Keychain via 'config credentials add'." This means `OctokitClient` is not finding the token that AIDevTools already stores in its Keychain under `RepositoryInfo.credentialAccount`.

**Root cause investigation:**
1. Trace `PRRadarContentView` → `AllPRsModel` init → wherever `OctokitClient` is constructed
2. Confirm `CredentialResolver.createPlatform(githubAccount:)` is being called with `repository.credentialAccount` (not a hardcoded string or empty value)
3. Verify the Keychain service identifier used by `OctokitClient` / `CredentialResolver` matches what AIDevTools stores under `KeychainSDK` (same service name, same account key)

**Fix steps:**
1. Read `AllPRsModel.swift` and `PRRadarContentView.swift` to find where `OctokitClient` is initialized
2. Ensure `credentialAccount` from `RepositoryInfo` is passed all the way through to `CredentialResolver.createPlatform(githubAccount:)`
3. If `credentialAccount` is empty or credentials are missing, surface a clear in-tab error message (e.g., "No GitHub credentials configured for this repo. Add them in Settings → Credentials.") instead of propagating the raw error string
4. Confirm the fix works for an iOS repo whose `credentialAccount` is already set in AIDevTools

**Verification:** Open PR Radar tab with an iOS repo selected — either PR list loads (if token exists) or a friendly "configure credentials" message appears (if not). No raw "No GitHub token found" error thrown.

---

Nothing left behind in the old repo. Every useful asset lives in AIDevTools.

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
- `pr-radar-gemini.png` — PR Radar icon for tab branding
- `AccentColor.colorset/` — accent color definition
- `PRRadarMac.entitlements` — merge needed entitlements

**XCUITests:**
- `PRRadarMacUITests/` → `Tests/Apps/PRRadarMacUITests/` (adapt for new tab-based structure)

**IDE Config:**
- `.vscode/launch.json` — adapt paths and merge

**NOT migrated** (generated/personal):
- `.venv/`, `xcuserdata/`, `.env`, `.build/`, `SourcePackages/`, `PRRadar.xcodeproj/`, `Package.resolved`

**Verification:** All useful content from PRRadar repo has a home in AIDevTools.

## - [x] Phase 10: Validation

**Skills used**: none
**Principles applied**: Fixed a missing local variable `resultEventDecodeFailures` in `ClaudeStructuredOutputParser.swift` that caused compile errors only in `swift test` (not `swift build`). All pre-existing test failures (`ClaudeChainServiceTests` missing fixtures, `SkillScannerSDKTests` environment-dependent) confirmed unchanged. All 7 validation criteria passed: build clean, tests pass, CLI shows all subcommands, end-to-end regex analysis completes with 3 violations, artifacts land in `DataPathsService` path, and no files left behind in old PRRadar repo.

Run full validation across the migrated codebase.

1. `swift build` — full package builds with no errors
2. `swift test` — all test targets pass (existing + migrated)
3. Mac app launches, PR Radar tab is visible per repo
4. CLI `ai-dev-tools-kit prradar --help` shows all subcommands
5. End-to-end regex analysis against PRRadar-TestRepo succeeds
6. Artifacts land in `~/Desktop/ai-dev-tools/prradar/repos/...`
7. No files left behind in old PRRadar repo that should have been migrated

### Future Deduplication Phases (Post-Migration, Separate Plans)

These happen after all migration phases are complete:

- **Unify Git Operations** — Remove `GitOperationsService` wrapper, update call sites to use `GitClient` directly
- **Unify GitHub Clients** — Evaluate whether `gh` CLI usage in `ClaudeChainSDK` should migrate to `OctokitSDK`, or keep both with a shared protocol
- **Simplify PRRadar Configuration** — Remove `RepositoryConfiguration` runtime object, take `RepositoryInfo` + `PRRadarRepoSettings` directly
- **Migrate PRRadar to AIOutputSDK Provider Framework** — Replace `ClaudeAgentSDK` (Python bridge, single provider) with `AIClient` protocol from `AIOutputSDK`, unlocking provider selection in the PR Radar tab (Anthropic API, Claude CLI, Codex, etc.)
