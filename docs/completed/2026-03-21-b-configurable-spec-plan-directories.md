## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer Swift app architecture (Apps, Features, Services, SDKs) |
| `swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns, observable models, state management |

## Background

Plans currently live in two separate locations:

1. **In-repo plans** — in the repo at `docs/proposed/`, committed to version control
2. **Machine-generated plans** — external at `~/Desktop/ai-dev-tools/<repoId>/<job-name>/plan.md`, executed by `ExecutePlanUseCase`

Both use the same `## - [x]` / `## - [ ]` phase format. Having two locations is confusing and means the Mac app only shows generated plans.

**Unified approach:** All plans live in the same repo-relative directory. By default, new plans go in `docs/proposed/` and completed plans move to `docs/completed/`. Both directories are configurable per-repo.

**Goals:**
1. Unify plan storage — `GeneratePlanUseCase` writes to the repo's proposed directory instead of the external data path
2. Per-repo configurable directories for proposed and completed plans (repo-relative or absolute, defaults: `docs/proposed`, `docs/completed`)
3. Settings editable via UI and CLI
4. Mac app Plans section shows all plans from the configured directory
5. Remove dependency on `JobDirectory` for plan storage (keep it only if needed for worktrees/logs)

## Phases

## - [x] Phase 1: Add plan directories to per-repo settings

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Followed EvalRepoSettingsStore pattern in Services layer; store is a Sendable struct with JSON persistence; WorkspaceModel integration follows existing injection pattern

**Skills to read**: `swift-app-architecture:swift-architecture`

Follow the existing `EvalRepoSettingsStore` pattern — create a parallel settings store for plan directory config.

- Create `PlanRepoSettings` model with fields:
  - `proposedDirectory: String?` — repo-relative or absolute path, defaults to `docs/proposed` when nil
  - `completedDirectory: String?` — repo-relative or absolute path, defaults to `docs/completed` when nil
- Create `PlanRepoSettingsStore` in `PlanRunnerService` (Services layer):
  - Persists to `plan-settings.json` in the data path
  - Keyed by repo UUID
  - CRUD operations: `settings(forRepoId:)`, `update(repoId:proposedDirectory:completedDirectory:)`, `remove(repoId:)`
  - Helper: `resolvedProposedDirectory(repoPath:)` and `resolvedCompletedDirectory(repoPath:)` that resolve relative paths against the repo path
- Add `PlanRepoSettingsStore` to `WorkspaceModel` init (same pattern as `EvalRepoSettingsStore`)
- Write unit tests in `PlanRunnerServiceTests`

## - [x] Phase 2: Migrate GeneratePlanUseCase to write plans into the repo

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Use cases orchestrate; closure-based dependency injection avoids coupling Features to Services configuration; PlanEntry moved to Services as shared model

**Skills to read**: `swift-app-architecture:swift-architecture`

- Update `GeneratePlanUseCase` to accept a `proposedDirectory: URL` parameter (the resolved directory) instead of writing to `JobDirectory`
  - Write plan files directly into the proposed directory using the generated filename (e.g. `docs/proposed/test-validation.md`)
  - Create the directory if it doesn't exist
  - Remove `JobDirectory.create` usage from plan generation
  - **Note:** The use case does repo matching internally (voice text → repo). The caller must resolve the proposed directory for the matched repo *after* matching completes. Either pass a closure that resolves the directory given a `RepositoryInfo`, or split into two steps (match first, then generate with the resolved directory). The use case must not access `PlanRepoSettingsStore` directly (that would couple Features to Services configuration).
- Update `ExecutePlanUseCase.moveToCompleted` to move plans from the proposed directory to the completed directory (both passed as parameters)
- Update CLI commands (`PlanRunnerPlanCommand`, `PlanRunnerExecuteCommand`) to resolve directories from `PlanRepoSettingsStore` and pass them to use cases
- Update `PlanRunnerDeleteCommand` to work with in-repo plan files instead of `JobDirectory`

## - [x] Phase 3: Expose plan directories in Settings UI and CLI

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: Followed existing ConfigurationEditSheet/ConfigurationDetailView pattern for new fields; CLI options mirror eval settings pattern with --proposed-dir and --completed-dir

**Skills to read**: `swift-app-architecture:swift-swiftui`

- Update `RepositoriesSettingsView` to show and edit proposed/completed directories alongside the existing cases directory field
- Update `ReposCommand` CLI:
  - `repos list` shows proposed/completed directories
  - `repos add` accepts `--proposed-dir` and `--completed-dir` options
  - `repos update` accepts `--proposed-dir` and `--completed-dir` options
- Update `WorkspaceModel` with accessor methods for the plan settings (same pattern as `casesDirectory(for:)`)

## - [x] Phase 4: Update Mac app Plans section to use repo directory

**Skills used**: `swift-app-architecture:swift-swiftui`
**Principles applied**: Extracted file scanning logic into LoadPlansUseCase (Features layer) per MV pattern — models delegate to use cases, not implement business logic; moved relative path computation to PlanEntry domain model

**Skills to read**: `swift-app-architecture:swift-swiftui`

- Rewrite `PlanRunnerModel.loadPlans` to scan the resolved proposed directory for `.md` files containing phase headings (`## - [x]` or `## - [ ]`) instead of using `JobDirectory.list()`
- Update `PlanEntry` to hold a `fileURL: URL` instead of a `JobDirectory`
- Update `PlanDetailView`:
  - Load plan content from `fileURL` instead of `jobDirectory.planURL`
  - Execute button calls `ExecutePlanUseCase` with the plan file path
  - Show file path relative to repo root
- Update delete to remove the file from the repo directory
- Remove the separate "Generated Plans" vs "Spec Plans" distinction — they're all just plans now

## - [x] Phase 5: Clean up obsolete code

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Removed dead JobDirectory code entirely; ExecutePlanUseCase Options kept simple with resolved values passed by callers; repo matching moved from CLI to use case callers who have access to stores

**Skills to read**: `swift-app-architecture:swift-architecture`

- Evaluate whether `JobDirectory` is still needed. If only used for plan storage (not worktrees/logs elsewhere), remove it from `PlanRunnerService`
- Remove any leftover `JobDirectory.list()` / `deriveRepoId` usage from the Mac app
- Clean up the repo name vs UUID matching workaround in `loadPlans`
- Verify no orphaned external plans need manual migration (document how to move existing `~/Desktop/ai-dev-tools/<repoId>/*/plan.md` files into repo `docs/proposed/` if desired)

## - [x] Phase 6: Validation

**Skills used**: `swift-testing`
**Principles applied**: Ran full test suite (261 tests, 0 failures); verified Mac app build; validated CLI repos list/update with plan directory options

**Skills to read**: `swift-testing`

- Run full test suite: `swift test`
- Build Mac app and verify:
  - Settings UI shows proposed/completed directory fields per repo
  - Plans section shows all `.md` files with phase headings from `docs/proposed/`
  - Generating a plan writes to `docs/proposed/` in the matched repo
  - Executing a plan works from the repo directory
  - Completed plans move to `docs/completed/`
  - Deleting a plan removes the file
- CLI verification:
  - `repos list` shows plan directories
  - `repos update <uuid> --proposed-dir specs/` updates the setting
  - `plan-runner plan "..."` writes to the repo's proposed directory
  - `plan-runner execute --plan <path>` works with repo-relative plans
  - `plan-runner delete --plan <path>` removes the file
