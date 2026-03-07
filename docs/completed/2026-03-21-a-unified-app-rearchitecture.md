## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer Swift app architecture (Apps, Features, Services, SDKs) |
| `swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns, observable models, state management |
| `swift-testing` | Test style guide and conventions |

## Background

The app currently has two independent verticals — **Evals** and **Plan Runner** — that each manage repository information separately and have disconnected UIs (Evals has a Mac app UI, Plan Runner is CLI-only). Additionally, the Mac app UI is organized around "Skills" (`SkillBrowserView`), but the app's scope is broader than skills alone.

**Current duplication:**
- **Two repo models**: `RepositoryConfiguration` (SkillService — UUID, path, name, casesDirectory) and `Repository` (PlanRunnerService — string id, path, description, skills, verification, pullRequest, githubUser)
- **Two repo stores**: `RepositoryConfigurationStore` persists to `dataPath/repositories.json`, while `ReposConfig` loads from `~/Desktop/ai-dev-tools/repos.json`
- **No shared layer**: Each feature independently defines what a "repository" is

**Goals:**
1. **Unified UI** — A single Mac app where you can run evals *or* do planning from the same interface
2. **Generalized navigation** — The UI currently revolves around skills; it should become a general-purpose workspace that includes skills, planning, and future capabilities
3. **Shared repository layer** — One model and one store for repository information, used by both Evals and Plan Runner

## Phases

## - [x] Phase 1: Create a shared RepositorySDK

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Stateless SDK struct with no app-specific dependencies; Sendable types; alphabetical ordering in Package.swift

**Skills to read**: `swift-app-architecture:swift-architecture`

Introduce a new `RepositorySDK` module in the SDKs layer that becomes the single source of truth for repository information.

- Create `Sources/SDKs/RepositorySDK/` with:
  - `RepositoryInfo.swift` — Unified model merging fields from both `RepositoryConfiguration` and `Repository`. Key fields: `id` (UUID), `path` (URL), `name` (String), `description` (String?), `githubUser` (String?), `verification` (commands/notes), `pullRequest` (baseBranch, naming, template), `skills` ([String]?), `architectureDocs` ([String]?), `recentFocus` (String?). Note: `casesDirectory` is NOT on this model — it lives in `EvalRepoSettingsStore` (EvalService layer) since it is eval-specific.
  - `RepositoryStore.swift` — Unified persistence (replaces both `RepositoryConfigurationStore` and `ReposConfig`). Single JSON file. Supports load, add, update, remove, lookup by ID/path.
  - `RepositoryStoreConfiguration.swift` — Data path configuration (replaces `SkillServiceConfiguration`)
- Add `RepositorySDK` target to Package.swift
- Write unit tests in `Tests/SDKs/RepositorySDKTests/`

## - [x] Phase 2: Migrate SkillService and SkillBrowserFeature to RepositorySDK

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Completed alongside Phase 1 — old types (RepositoryConfiguration, RepositoryConfigurationStore, SkillServiceConfiguration) were removed; all SkillBrowserFeature use cases, CLI commands, and Mac app models already use RepositorySDK types (RepositoryInfo, RepositoryStore)

**Skills to read**: `swift-app-architecture:swift-architecture`

Replace `RepositoryConfiguration` and `RepositoryConfigurationStore` usage with the new shared types.

- Update `SkillService` to depend on `RepositorySDK` instead of defining its own repo model
  - Remove `RepositoryConfiguration.swift`, `RepositoryConfigurationStore.swift`, `SkillServiceConfiguration.swift`
  - Keep `Skill.swift` and `PathUtilities.swift` (these are skill-specific)
- Update `SkillBrowserFeature` use cases (`LoadRepositoriesUseCase`, `AddRepositoryUseCase`, `RemoveRepositoryUseCase`, `UpdateRepositoryUseCase`) to use `RepositoryInfo` and `RepositoryStore`
- Update `EvalService` if it references `SkillServiceConfiguration` paths
- Update CLI commands (`ReposCommand` and subcommands, `SkillsCommand`) to use new types
- Update all tests that reference the old types
- Ensure the app still compiles and existing tests pass

**Note:** `casesDirectory` has been moved out of `RepositoryInfo` (SDK layer) and into `EvalRepoSettings` / `EvalRepoSettingsStore` in the EvalService layer, since it is eval-specific. CLI commands and the Mac app now use `EvalRepoSettingsStore` for cases directory lookup. Eval settings are persisted in a separate `eval-settings.json` file.

## - [x] Phase 3: Migrate PlanRunnerService to RepositorySDK

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Replaced `Repository`/`ReposConfig` with `RepositoryInfo`/`RepositoryStore`; removed `--config` option from CLI; `JobDirectory` kept as-is in PlanRunnerService (plan-specific); `RepoMatch.repoId` stays String since it's a Claude response parsed to UUID at call site

**Skills to read**: `swift-app-architecture:swift-architecture`

Replace `Repository`, `ReposConfig`, and the separate `repos.json` with the shared store.

- Update `PlanRunnerService` to depend on `RepositorySDK`
  - Remove `Models/Repository.swift` and `Models/ReposConfig.swift`
  - Keep `JobDirectory.swift` (plan-specific storage)
- Update `PlanRunnerFeature` use cases (`GeneratePlanUseCase`, `ExecutePlanUseCase`) to accept `RepositoryInfo` instead of `Repository`
  - Update Claude prompts that serialize repo metadata (verification commands, PR config, skills, etc.) to pull from `RepositoryInfo` fields
- Update `PlanRunnerFeature/services/ClaudeResponseModels.swift` — `RepoMatch` should reference the shared repo ID type
- Update CLI commands (`PlanRunnerPlanCommand`, `PlanRunnerExecuteCommand`) to load repos from `RepositoryStore` instead of `ReposConfig`
  - Remove `--config` option that pointed to the old `repos.json`
- Update `RepositoryConfigurationStore+CLI.swift` to work with `RepositoryStore`
- Update all tests
- Ensure CLI plan-runner commands still work end-to-end

## - [x] Phase 4: Manually migrate existing data files

**Principles applied**: One-time manual data migration — merged 2 SkillService repos and 6 PlanRunner repos into unified `repositories.json` (8 total); extracted `casesDirectory` values into `eval-settings.json`; deleted old `repos.json`

No runtime migration code needed — Bill is the only user. Instead, manually convert the existing data files once:

- Read the current `repositories.json` (SkillService format) and `repos.json` (PlanRunner format) from `~/Desktop/ai-dev-tools/`
- Write a single unified `repositories.json` in the new `RepositoryInfo` format, merging fields from both sources (match by path)
- Extract `casesDirectory` values from repositories and write them to `eval-settings.json` (keyed by repo UUID)
- Delete the old `repos.json` after merging
- Verify the app and CLI load the new file correctly

## - [x] Phase 5: Generalize the Mac app navigation from Skills to Workspace

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: Model-View pattern with `@Observable` WorkspaceModel; view-owned selection via `@State`/`@AppStorage`; sectioned List in content column for extensible navigation

**Skills to read**: `swift-app-architecture:swift-swiftui`

Rename and restructure the UI so it's no longer skills-specific. The sidebar should show repositories, and the detail area should offer tabs/sections for different capabilities.

- Rename `SkillBrowserView` → `WorkspaceView` (or similar)
- Rename `SkillBrowserModel` → `WorkspaceModel`
- Restructure the 3-column layout:
  - **Sidebar**: Repository list (same as current)
  - **Content column**: Navigation for the selected repo — sections like "Skills", "Plans", and future items
  - **Detail column**: Content for the selected section item
- The "Skills" section retains current skill list + skill detail + eval results behavior
- Add a "Plans" section (placeholder for Phase 6)
- Update `AIDevToolsApp.swift` to use new model/view names
- Update Settings views if they reference old names

## - [x] Phase 6: Add Plan Runner UI

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: Model-View pattern with `@Observable` PlanRunnerModel; view-owned selection via `@State`/`@AppStorage`; execution progress streamed via `@Sendable` callback with MainActor hop; plan content and phases as view-scoped `@State`; counter-based change detection to avoid Equatable requirement on state enum

**Skills to read**: `swift-app-architecture:swift-swiftui`

Build a UI for the plan runner inside the new workspace navigation.

- Create a `PlanListView` showing plans from `JobDirectory.list()` for the selected repository
  - Display plan name, status (pending phases vs completed), creation date
- Create a `PlanDetailView` showing:
  - Plan markdown content (rendered)
  - Phase checklist with status indicators
  - Execute button that runs `ExecutePlanUseCase` with progress
  - Live output/progress display (similar to `EvalResultsView`'s progress pattern)
- Create a `PlanRunnerModel` (@Observable) to manage plan state, similar to `EvalRunnerModel`:
  - Load plans for repo, track execution progress, update phase status
- Wire into the "Plans" section added in Phase 5
- Also consider a "Generate Plan" action (voice text input → `GeneratePlanUseCase`)

## - [x] Phase 7: Clean up Package.swift and dead code

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Removed 4 transitive-only CLI dependencies (EvalSDK, GitSDK, SkillScannerSDK, SkillService); sorted test targets alphabetically per project conventions; verified no orphaned targets or dead code from prior migrations

**Skills to read**: `swift-app-architecture:swift-architecture`

- Remove now-unused targets/products if any modules were fully absorbed (e.g., if `SkillServiceConfiguration` was the only reason for certain dependencies)
- Verify all target dependency lists are minimal and correct
- Remove any orphaned test targets
- Ensure alphabetical ordering in Package.swift target lists per project conventions

## - [x] Phase 8: Validation

**Skills used**: `swift-testing`
**Principles applied**: Verified full test suite (256 tests), Mac app build, CLI commands (repos list, plan-runner plan/execute/delete); fixed plan generation (--verbose flag), error display, plan loading on view appear, and added delete capability

**Skills to read**: `swift-testing`

- Run full test suite: `swift test` in AIDevToolsKit
- Build and run the Mac app in Xcode — verify:
  - Repository management (add/remove/update) works in Settings
  - Skills browsing and eval running works as before
  - Plan section appears and lists plans for selected repo
  - Plan execution works from the UI
- Run CLI commands to verify:
  - `ai-dev-tools-kit repos list` shows unified repo list
  - `ai-dev-tools-kit run-evals --repo <path>` still works
  - `ai-dev-tools-kit plan-runner plan "..."` works with unified repo store
  - `ai-dev-tools-kit plan-runner execute --plan <path>` works
- Verify data migration: place old-format `repositories.json` and `repos.json` in data directory, confirm they merge correctly on first run
