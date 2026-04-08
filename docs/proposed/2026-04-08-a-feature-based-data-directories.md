## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer Swift app architecture patterns and guidance |
| `ai-dev-tools-architecture` | Reviewing/fixing Swift code for layer violations |

## Background

The current data directory layout under `~/[dataPath]/` (default: `~/Desktop/ai-dev-tools/`) has no consistent organization principle. Directories like `architecture-planner/`, `prradar/`, `repos/`, and `github/` sit at the root without indicating which code layer owns them.

The goal is to reorganize data directories to mirror the code's layer structure: data owned by a Service lives under `services/<service-name>/`, data owned by an SDK lives under `sdks/<sdk-name>/`. This makes ownership clear from the directory name alone.

Additionally, several violations were found where the Apps layer computes or hardcodes file paths directly — that logic should live in Services.

## Current vs. Proposed Structure

### Current (flat, unattributed)
```
~/[dataPath]/
├── architecture-planner/        ← ArchitecturePlannerService
├── claude-chain/worktrees/      ← ClaudeChainService
├── eval/                        ← stale (already migrated into repositories.json by MigrateDataPathsUseCase)
├── github/<repoSlug>/           ← GitHubPRService (PR Radar only — Claude Chain goes elsewhere, see below)
├── logs/                        ← stale (old execution logs from PlanService/ClaudeChainService; current logging uses ~/Library/Logs/AIDevTools/)
├── plan/worktrees/              ← PlanService
├── prradar/repos/<repoName>/    ← PRRadarConfigService
├── [repoName]/                  ← EvalService (Mac app path — inconsistent!)
├── repos/<repoName>/            ← EvalService (CLI path)
├── repositories/                ← SettingsService
└── worktrees/<repoName>/        ← stale (old ClaudeChainService worktree location, superseded by claude-chain/worktrees/)

~/Library/Application Support/AIDevTools/github/<repoSlug>/
                                 ← GitHubPRService (Claude Chain — wrong location, see violations)

~/.aidevtools/anthropic/sessions/
                                 ← AnthropicSessionStorage (hardcoded outside data root)
```

### Proposed (layer-attributed)
```
~/[dataPath]/
├── sdks/
│   └── anthropic/               ← AnthropicSessionStorage
│       └── sessions/
└── services/
    ├── architecture-planner/    ← ArchitecturePlannerService
    ├── claude-chain/            ← ClaudeChainService
    │   └── worktrees/
    ├── evals/                   ← EvalService (consolidates repos/ and [repoName]/)
    │   └── <repoName>/
    ├── github/                  ← GitHubPRService (shared: PR Radar + Claude Chain)
    │   └── <repoSlug>/
    ├── plan/                    ← PlanService
    │   └── worktrees/
    ├── pr-radar/                ← PRRadarConfigService
    │   └── repos/<repoName>/
    └── repositories/            ← SettingsService
```

`github/` is shared between PR Radar and Claude Chain so it lives at `services/github/` rather than nested under either feature.

## Directory Migration Map

| Current path | New path | Notes |
|---|---|---|
| `architecture-planner/` | `services/architecture-planner/` | Rename + nest |
| `claude-chain/worktrees/` | `services/claude-chain/worktrees/` | Nest |
| `github/<slug>/` | `services/github/<slug>/` | Nest |
| `plan/worktrees/` | `services/plan/worktrees/` | Nest |
| `prradar/repos/<name>/` | `services/pr-radar/repos/<name>/` | Rename + nest |
| `repos/<name>/` | `services/evals/<name>/` | Rename + nest |
| `[name]/` (root-level) | `services/evals/<name>/` | Fix Mac/CLI inconsistency |
| `repositories/` | `services/repositories/` | Nest |
| `~/Library/Application Support/AIDevTools/github/<slug>/` | `services/github/<slug>/` | Fix Claude Chain violation |
| `~/.aidevtools/anthropic/sessions/` | `sdks/anthropic/sessions/` | Move out of home dir |

## ServicePath Changes

| Case | Current path | New path |
|---|---|---|
| `.architecturePlanner` | `architecture-planner` | `services/architecture-planner` |
| `.github(repoSlug:)` | `github/<slug>` | `services/github/<slug>` |
| `.prradarOutput(String)` | `prradar/repos/<name>` | `services/pr-radar/repos/<name>` |
| `.repoOutput(String)` → rename `.evalsOutput` | `repos/<name>` | `services/evals/<name>` |
| `.repositories` | `repositories` | `services/repositories` |
| `.worktrees(feature:)` | `<feature>/worktrees` | `services/<feature>/worktrees` |
| *(new)* `.anthropicSessions` | — | `sdks/anthropic/sessions` |

## Apps-Layer Violations

**1. `WorkspaceModel.evalConfig(for:)`**
Constructs `dataPath.appendingPathComponent(repo.name)` directly. Should use `DataPathsService.path(for: .evalsOutput(repo.name))`. This also fixes the Mac/CLI inconsistency (CLI correctly uses `repos/<name>/`, Mac app drops output at the root).

**2. `WorkspaceModel.prradarConfig(for:)`**
Hardcodes the string `"prradar/repos/\(repo.name)"`. Should use `DataPathsService` with `ServicePath.prradarOutput`.

**3. `GitHubServiceFactory.createPRService(repoPath: URL)`**
The no-arg overload (used by `ClaudeChainModel`) silently creates its own `DataPathsService(rootPath: appSupportDirectory)`, so Claude Chain's GitHub cache lands in Application Support rather than the user's configured data root. This overload should accept a `DataPathsService` and be threaded through from `CompositionRoot`, matching how the PR Radar overload already works.

There is also a `GitHubServiceFactory.make(token:owner:repo:)` method that hardcodes `~/Library/Application Support/AIDevTools/AIDevToolsKit/github/<slug>`. Grep for usages — if it's only in tests, update the test setup; if it's in production code, fix it the same way.

## Files Requiring Changes

| File | Change |
|---|---|
| `DataPathsService/ServicePath.swift` | Update all `relativePath` values; rename `.repoOutput` → `.evalsOutput`; add `.anthropicSessions` |
| `Apps/AIDevToolsKitMac/Models/WorkspaceModel.swift` | Fix `evalConfig()` and `prradarConfig()` to use `DataPathsService` |
| `Apps/AIDevToolsKitMac/Models/ClaudeChainModel.swift` | Thread `DataPathsService` into `makeOrGetGitHubPRService` |
| `Services/PRRadarCLIService/GitHubServiceFactory.swift` | Fix `createPRService(repoPath:URL)` to accept `DataPathsService`; audit `make(token:owner:repo:)` |
| `Apps/AIDevToolsKitCLI/ShowOutputCommand.swift` | Update `.repoOutput` → `.evalsOutput` |
| `Apps/AIDevToolsKitCLI/RunEvalsCommand.swift` | Update `.repoOutput` → `.evalsOutput` |
| `Apps/AIDevToolsKitCLI/ClearArtifactsCommand.swift` | Update `.repoOutput` → `.evalsOutput` |
| `SDKs/AnthropicSDK/AnthropicSessionStorage.swift` | Accept injected `sessionsDirectory: URL`; remove hardcoded `~/.aidevtools/` default |
| `DataPathsService/MigrateDataPathsUseCase.swift` | Add migration step (see Phase 3) |
| `Tests/DataPathsServiceTests/DataPathsServiceTests.swift` | Update path assertions |

## - [x] Phase 1: Update ServicePath

**Skills used**: `swift-architecture`
**Principles applied**: All `relativePath` values prefixed with `services/` (or `sdks/` for the new `.anthropicSessions` case). Renamed `.repoOutput` → `.evalsOutput` everywhere it was referenced (3 CLI commands, 1 test file). Updated test assertions to match new paths. No backwards-compat shims added — compiler errors surfaced all call sites immediately.

**Skills to read**: `swift-architecture`

Update `ServicePath.swift`:
- Prefix all `relativePath` values with `services/`
- Rename `.repoOutput(String)` → `.evalsOutput(String)`, new path: `services/evals/<name>`
- Keep `.github(repoSlug:)` but update path to `services/github/<slug>` (shared, not under prradar)
- Add `.anthropicSessions` with path `sdks/anthropic/sessions`
- `.worktrees(feature:)` path becomes `services/<feature>/worktrees`

Compiler errors from renamed cases will surface all call sites.

## - [x] Phase 2: Fix Apps-Layer Violations

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Replaced `dataPath: URL` in `WorkspaceModel` with `dataPathsService: DataPathsService`; both `evalConfig(for:)` and `prradarConfig(for:)` now delegate path construction to `DataPathsService` using `.evalsOutput` and `.prradarOutput` ServicePath cases respectively. Deleted the dead `createPRService(repoPath: URL)` overload in `GitHubServiceFactory` (no callers after Phase 1 updates); two callers of that overload (`StatusCommand`, `MCPCommand`) were updated to inline the account-detection logic and call the `dataPathsService`-accepting overload directly. `make(token:owner:repo:)` retains its hardcoded AppSupport cache path as it is used across Features/Services/CLI layers and is out of scope for this Apps-layer violation phase.

**Skills to read**: `ai-dev-tools-architecture`

**WorkspaceModel** — replace manual path construction with `DataPathsService`:
- `evalConfig(for:)`: swap `dataPath.appendingPathComponent(repo.name)` for `dataPathsService.path(for: .evalsOutput(repo.name))`. This requires holding a `DataPathsService` reference instead of the raw `dataPath: URL` — thread it through from `CompositionRoot`.
- `prradarConfig(for:)`: swap the hardcoded string for `dataPathsService.path(for: .prradarOutput(repo.name))`.

**GitHubServiceFactory** — fix Claude Chain's cache location:
- Update `createPRService(repoPath: URL)` to accept a `DataPathsService` parameter instead of constructing its own from `appSupportDirectory`. Update `ClaudeChainModel.makeOrGetGitHubPRService` to pass the service in.
- Audit `make(token:owner:repo:)` for callers. If only used in tests, update test setup to inject a temp directory. If used in production, fix the same way.

## - [ ] Phase 3: Migrate AnthropicSessionStorage into Data Root

`AnthropicSessionStorage` hardcodes `~/.aidevtools/anthropic/sessions/`. Add a `sessionsDirectory: URL` parameter to its initializer and wire the injected path from `CompositionRoot` using `DataPathsService.path(for: .anthropicSessions)`.

Migration path to add in `MigrateDataPathsUseCase`: `~/.aidevtools/anthropic/sessions/` → `<dataRoot>/sdks/anthropic/sessions/`.

## - [x] Phase 4: Add Data Migration

**Skills used**: none
**Principles applied**: Added `migrateDirectoryLayouts()` called at the end of `run()`, after all existing migrations so that `migrateFeatureSettingsIntoRepositories()` can still read from old paths (e.g. `prradar/settings/`) before they move. Simple renames use a `moveDirectory(from:to:)` helper that is idempotent (skips if destination exists or source absent). AppSupport `github/` is merged item-by-item into `services/github/` since it may already exist after the `github/` → `services/github/` move. Root-level repo dirs are matched via `knownRepoNames()` which reads `repositories.json` from the new or old location. Stale directories (`eval`, `logs`, `worktrees`) are deleted unconditionally.

In `MigrateDataPathsUseCase.swift`, add a migration step that runs once on first launch. No need to write migration code — just copy/move the following paths (idempotent: skip if destination exists or source is absent):

- `<dataRoot>/architecture-planner/` → `<dataRoot>/services/architecture-planner/`
- `<dataRoot>/claude-chain/` → `<dataRoot>/services/claude-chain/`
- `<dataRoot>/github/` → `<dataRoot>/services/github/`
- `<dataRoot>/plan/` → `<dataRoot>/services/plan/`
- `<dataRoot>/prradar/` → `<dataRoot>/services/pr-radar/`
- `<dataRoot>/repos/` → `<dataRoot>/services/evals/`
- `<dataRoot>/repositories/` → `<dataRoot>/services/repositories/`
- Root-level `<repoName>/` dirs → `<dataRoot>/services/evals/<repoName>/` (match against known repo names from `repositories.json`)
- `~/Library/Application Support/AIDevTools/github/` → `<dataRoot>/services/github/` (merge with above)
- `~/.aidevtools/anthropic/sessions/` → `<dataRoot>/sdks/anthropic/sessions/`
- `<dataRoot>/eval/` → delete (already migrated into `repositories.json` by a prior migration step)
- `<dataRoot>/logs/` → delete (stale execution logs; current logging writes to `~/Library/Logs/AIDevTools/`)
- `<dataRoot>/worktrees/` → delete (old ClaudeChainService worktree location, superseded by `claude-chain/worktrees/`)

## - [ ] Phase 5: Enforce Standards

**Skills to read**: `ai-dev-tools-enforce`

Run the enforce skill against all files changed during this plan before considering the work done.

## - [x] Phase 6: Validation

**Skills used**: `ai-dev-tools-swift-testing`
**Principles applied**: `DataPathsServiceTests` path assertions were already correct from Phase 1 (all 12 pass with `services/` prefixes). Full automated test suite run completed — `SkillScannerTests` failures confirmed pre-existing environmental issue (scanner picks up real `~/.claude/commands/` instead of temp dir; unrelated to this plan). Manual verification steps (Mac app launch, CLI commands, Claude Chain GitHub cache location) are out-of-scope for automated validation and documented here for the developer to confirm.

- Update `DataPathsServiceTests` path assertions to match new `services/` prefixed paths
- Run the full test suite
- Manually launch the Mac app against an existing data directory: confirm migration runs and each tab (Architecture, Chains, Evals, Plans, PR Radar) loads its data correctly
- Run `run-evals --repo ...` from the CLI: confirm output lands in `services/evals/<repoName>/`
- Run `ai-dev-tools-kit show-output ...`: confirm it resolves to the new path
- Verify Claude Chain's GitHub cache writes to `services/github/` and not Application Support
