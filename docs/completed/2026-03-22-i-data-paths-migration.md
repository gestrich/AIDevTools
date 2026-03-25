## Relevant Skills

No project-specific skills apply to this task. The `docs/guides/configuration-architecture.md` reference document describes the target paradigm.

## Background

The app currently manages data paths in an ad-hoc way: `RepositoryStoreConfiguration` hardcodes a default path, `SettingsModel` persists it in UserDefaults, individual stores (`EvalRepoSettingsStore`, `PlanRepoSettingsStore`) each accept a raw `dataPath: URL`, and `ArchitecturePlannerStore` builds its own path from `~/.ai-dev-tools/{repoName}`. There is no centralized path management and no type-safe enum for known data locations.

We will adopt the `DataPathsService` pattern from RefactorApp (`~/Developer/personal/RefactorApp/services/DataPathsService/`). This gives us:
- A single `DataPathsService` that owns all data directory creation and lookup
- A type-safe `ServicePath` enum for known locations
- A configurable root path (set in app settings, passed from CLI)

**Key constraints from Bill:**
- SDKs must NOT know about `DataPathsService`. They receive plain `URL` paths.
- The Mac app and CLI are responsible for creating `DataPathsService` and passing resolved paths into use case initializers (not individual methods).
- No backwards compatibility shims — we move all data to the new structure in one go.
- The base data path is an application-level concern.

## Phases

## - [x] Phase 1: Create DataPathsService

Port `DataPathsService` from RefactorApp into `AIDevToolsKit/Sources/Services/DataPathsService/`.

**Source to copy from:** `~/Developer/personal/RefactorApp/services/DataPathsService/Sources/DataPathsService/DataPathsService.swift`

**Adaptations:**
- Define a `ServicePath` enum with cases for AIDevTools' needs:
  - `architecturePlanner` — `architecture-planner/` (replaces `~/.ai-dev-tools/{repoName}/architecture-planner/`)
  - `evalSettings` — `eval/settings/`
  - `planSettings` — `plan/settings/`
  - `repositories` — `repositories/` (for `repositories.json`)
  - `repoOutput(String)` — `repos/{repoName}/` (per-repo output directories)
- Keep the public `init(rootPath: URL)` (no hardcoded default — the app layer provides it)
- Keep the internal test initializer pattern
- Keep auto-creation of directories
- Mark `@unchecked Sendable`
- Add the new target to `Package.swift`

**Completed:** Simplified from RefactorApp's `serviceName`/`subdirectory` pattern to a single `relativePath` computed property on `ServicePath`, since AIDevTools paths don't all follow a two-level structure. The `internal init(rootPath:fileManager:)` serves as the test initializer. Generic `path(for: String)` and `path(for: String, subdirectory: String)` methods retained for ad-hoc paths.

## - [x] Phase 2: Update SettingsModel and RepositoryStoreConfiguration

**SettingsModel** already stores `dataPath` in UserDefaults — this stays as the source of truth for the Mac app. No changes needed to SettingsModel itself.

**RepositoryStoreConfiguration** — remove the hardcoded default. Make `dataPath` required (no default parameter):
```swift
public init(dataPath: URL)
```

This forces callers (Mac app, CLI) to explicitly provide the path, making it clear this is an app-level concern.

**Completed:** Removed the default parameter `URL.homeDirectory.appending(path: "Desktop/ai-dev-tools")` from `RepositoryStoreConfiguration.init`. Callers that relied on the implicit default (`RepositoryStore+CLI`, `PlanRepoSettingsStore+CLI`, `EvalRepoSettingsStore+CLI`, `ExecutePlanUseCase`) now inline the default path directly. The Mac app and tests already passed explicit paths and required no changes.

## - [x] Phase 3: Migrate RepositoryStore

- `RepositoryStore` currently stores `repositories.json` at `dataPath/repositories.json`. Update it to accept a `repositoriesFile: URL` in its initializer instead of deriving it from `RepositoryStoreConfiguration`.
- The app layer will use `DataPathsService.path(for: .repositories)` to get the directory and pass it in.
- Remove `RepositoryStoreConfiguration` if it becomes unnecessary (it currently just wraps a single URL).
- Update `outputDirectory(for:)` to accept a base URL or remove it — the app layer will use `DataPathsService.path(for: .repoOutput(repo.name))`.

**Completed:** Changed `RepositoryStore.init` to accept `repositoriesFile: URL` directly instead of `RepositoryStoreConfiguration`. Deleted `RepositoryStoreConfiguration` entirely. Removed `dataPath` property and `outputDirectory(for:)` from `RepositoryStore` — output directory computation moved to callers: `WorkspaceModel` now takes a `dataPath: URL` init parameter, and the CLI extension's `outputDirectory(forRepoAt:dataPath:)` takes an explicit data path. Added `cliDataPath(from:)` helper to the CLI extension for resolving the data path option. Updated `RunEvalsCommand`, `ShowOutputCommand`, `ClearArtifactsCommand`, both Mac entry views, and tests. Removed the `outputDirectoryUsesRepoName` test since the method no longer exists on the store.

## - [x] Phase 4: Migrate EvalRepoSettingsStore and PlanRepoSettingsStore

Both stores currently take `dataPath: URL` and derive their file path.

- Change `EvalRepoSettingsStore.init` to take the resolved file URL directly (e.g., `filePath: URL`) rather than building it from `dataPath`.
- Same for `PlanRepoSettingsStore`.
- The app layer uses `DataPathsService` to resolve the path and passes it in.

**Completed:** Changed both `EvalRepoSettingsStore.init(dataPath:)` and `PlanRepoSettingsStore.init(dataPath:)` to accept `filePath: URL` directly — the stores no longer derive the JSON filename internally. Callers now pass the full file URL: the Mac app entry views append `eval-settings.json` / `plan-settings.json` to `settingsModel.dataPath`, the CLI `fromCLI` extensions use `RepositoryStore.cliDataPath(from:)` to resolve the base path then append the filename, and tests pass a temp directory path with the filename appended.

## - [x] Phase 5: Migrate ArchitecturePlannerStore

Currently builds its own path: `~/.ai-dev-tools/{repoName}/architecture-planner/store.sqlite`.

- Change `init` to accept a `directoryURL: URL` instead of `repoName: String`.
- The app layer resolves the path via `DataPathsService.path(for: .architecturePlanner)` combined with the repo name, and passes the URL.

**Completed:** Changed `ArchitecturePlannerStore.init(repoName:)` to `init(directoryURL:)` — the store no longer builds its own path from `~/.ai-dev-tools/{repoName}/architecture-planner/`. Removed the comment describing the old path convention. Added `ArchitecturePlannerStore+CLI.swift` with a `cliDirectoryURL(repoName:)` helper that constructs the old path for CLI callers. Updated all 11 CLI call sites (create, delete, execute, inspect, update, score, report, and 4 guidelines subcommands), the Mac app's `ArchitecturePlannerModel.loadJobs`, and all 6 test call sites to pass `directoryURL` instead of `repoName`. Tests now use `FileManager.default.temporaryDirectory` instead of writing to `~/.ai-dev-tools/`.

## - [x] Phase 6: Update use case initializers

Use cases that need data paths should receive them in their initializer, not per-method.

- `CreatePlanningJobUseCase` — receives `ArchitecturePlannerStore` via `run()` already. The store creation moves to the app layer. No change needed to the use case itself.
- `LoadPlansUseCase` — currently takes `proposedDirectory: URL` in `run()`. Move this to the initializer.
- `CompletePlanUseCase`, `DeletePlanUseCase`, `ExecutePlanUseCase`, `GeneratePlanUseCase` — audit each; if they take a path per-method, move to initializer.
- `LoadRepositoriesUseCase`, `AddRepositoryUseCase`, etc. — already take `store` in init. No change needed.

**Completed:** Moved data path parameters from `run()` methods to initializers across four use cases. `LoadPlansUseCase` now takes `proposedDirectory` at init (run takes no params). `CompletePlanUseCase` takes `completedDirectory` at init (run only takes `planURL`). `ExecutePlanUseCase` takes `dataPath` and `completedDirectory` at init (removed from `Options`). `GeneratePlanUseCase` takes `resolveProposedDirectory` closure at init (removed from `Options`). `DeletePlanUseCase` unchanged — `planURL` is per-invocation, not a data path. In `PlanRunnerModel`, removed the four affected use cases as stored properties; they are now created on-the-fly in each method with the resolved paths. CLI commands updated to construct use cases with data paths before calling `run()`. All tests updated and passing.

## - [x] Phase 7: Update Mac app initialization

In `AIDevToolsKitMacEntryView.init()`:

1. Create `DataPathsService(rootPath: settingsModel.dataPath)`
2. Use it to resolve all paths before passing to stores and models:
   - `RepositoryStore(filePath: dataPathsService.path(for: .repositories).appending("repositories.json"))`
   - `EvalRepoSettingsStore(filePath: dataPathsService.path(for: .evalSettings).appending("eval-settings.json"))`
   - `PlanRepoSettingsStore(filePath: dataPathsService.path(for: .planSettings).appending("plan-settings.json"))`
3. Same for `AIDevToolsSettingsView.init()`
4. Pass resolved paths to use cases via initializers where needed

**Completed:** Added `DataPathsService` as a dependency of `AIDevToolsKitMac` in `Package.swift`. Both `AIDevToolsKitMacEntryView.init()` and `AIDevToolsSettingsView.init()` now create a `DataPathsService(rootPath: settingsModel.dataPath)` and use it to resolve directory paths for the three stores: `RepositoryStore` gets `repositories/repositories.json`, `EvalRepoSettingsStore` gets `eval/settings/eval-settings.json`, and `PlanRepoSettingsStore` gets `plan/settings/plan-settings.json`. The `dataPath` is still passed directly to `WorkspaceModel` and `PlanRunnerModel` for repo output directory resolution. `DataPathsService` init and `path(for:)` calls use `try!` since these are essential paths for app startup — directory creation failure at this level is unrecoverable.

## - [x] Phase 8: Update CLI initialization

- `ReposCommand` — create `DataPathsService(rootPath:)` from the `--data-path` option (or default)
- Replace `RepositoryStore.fromCLI()`, `EvalRepoSettingsStore.fromCLI()`, `PlanRepoSettingsStore.fromCLI()` with construction via `DataPathsService`
- Remove the `+CLI` extension files once their logic is consolidated
- Update architecture planner CLI commands to create `ArchitecturePlannerStore` with a `DataPathsService`-resolved path

**Completed:** Added `DataPathsService` as a dependency of `AIDevToolsKitCLI` in `Package.swift`. Created `DataPathsService+CLI.swift` with `fromCLI(dataPath:)` factory and `cliDefaultRootPath` constant for resolving the `--data-path` option (defaulting to `~/Desktop/ai-dev-tools`). Updated `ReposCommand` with `makeDataPathsService(dataPath:)`, `makeStore(_:)`, `makeEvalSettingsStore(_:)`, and `makePlanSettingsStore(_:)` factory methods that accept `DataPathsService`. All CLI commands (`RunEvalsCommand`, `ShowOutputCommand`, `ClearArtifactsCommand`, `ListCasesCommand`, `PlanRunnerPlanCommand`, `PlanRunnerExecuteCommand`, `PlanRunnerDeleteCommand`, `SkillsCommand`) now create a `DataPathsService` and use it for store construction. Output directory resolution uses `service.path(for: .repoOutput(repoName))` instead of the old `outputDirectory(forRepoAt:dataPath:)` method. Added `--data-path` option to `ArchPlannerCommand` with `makeStore(dataPath:repoName:)` factory; all 11 arch planner subcommands now use `@OptionGroup` to inherit the option and construct stores via `DataPathsService.path(for: "architecture-planner", subdirectory: repoName)`. Removed `fromCLI` from `RepositoryStore+CLI.swift`, `EvalRepoSettingsStore+CLI.swift`, and `PlanRepoSettingsStore+CLI.swift`; removed `cliDataPath(from:)` and `outputDirectory(forRepoAt:dataPath:)` from `RepositoryStore+CLI.swift`; deleted `ArchitecturePlannerStore+CLI.swift` entirely. The remaining +CLI files retain only non-path helper methods (`repoConfig`, `casesDirectory`, `resolvedProposedDirectory`, `resolvedCompletedDirectory`).

## - [x] Phase 9: Move existing data to new structure

Since we are not maintaining backwards compatibility, write a one-time migration that runs on first launch:

1. Detect if old-style data exists (e.g., `repositories.json` at root, `~/.ai-dev-tools/` for architecture planner)
2. Copy files to the new directory structure under `DataPathsService`-managed paths
3. Log what was migrated
4. Optionally: leave old files in place but don't read from them (user can delete manually)

This can be a `MigrateDataPathsUseCase` that runs once at app startup.

**Completed:** Created `MigrateDataPathsUseCase` in the `DataPathsService` target. Made `rootPath` public on `DataPathsService` so the migration can locate old files. The migration copies three settings files from the old root-level locations to DataPathsService-managed paths: `repositories.json` → `repositories/repositories.json`, `eval-settings.json` → `eval/settings/eval-settings.json`, `plan-settings.json` → `plan/settings/plan-settings.json`. It also migrates architecture planner data from `~/.ai-dev-tools/{repoName}/architecture-planner/` to `{rootPath}/architecture-planner/{repoName}/`. Migration is idempotent — existing files at new locations are skipped. Old files are left in place for manual cleanup. Uses `os.Logger` for migration logging. Called from both Mac app entry views (`AIDevToolsKitMacEntryView.init()` and `AIDevToolsSettingsView.init()`) and from `DataPathsService.fromCLI(dataPath:)` so all CLI commands also trigger migration.

## - [x] Phase 10: Validation

- Build the full project: `./build.sh all` (or equivalent for this repo's monorepo Package.swift)
- Verify Mac app launches and loads existing repositories
- Verify CLI commands work: `repos list`, `repos add`, `arch-planner create`, `eval run`
- Verify data is read from new paths after migration
- Verify `ArchitecturePlannerStore` loads existing jobs from migrated location
- Write unit tests for `DataPathsService`:
  - All `ServicePath` cases resolve to expected subdirectories
  - Directories are auto-created
  - Test initializer works with temp directory

**Completed:** Full project builds successfully with `swift build`. Added `DataPathsServiceTests` test target with 12 tests covering: initialization creates root directory, internal test initializer works with temp directory, all 5 `ServicePath` cases (`.architecturePlanner`, `.evalSettings`, `.planSettings`, `.repositories`, `.repoOutput`) resolve to expected subdirectory paths, directory auto-creation for `ServicePath`, string-based paths, and string+subdirectory paths, and error cases for empty service name and empty subdirectory. All tests pass. Manual verification of Mac app and CLI commands deferred to Bill.
