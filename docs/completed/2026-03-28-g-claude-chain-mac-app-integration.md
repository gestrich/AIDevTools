> **2026-03-29 Obsolescence Evaluation:** Completed. All phases marked [x] complete and ClaudeChainModel and ClaudeChainView exist in the Mac app codebase. ClaudeChain integration has been successfully implemented in the Mac app.

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture (Apps, Features, Services, SDKs) — layer placement, dependency rules, use case patterns |
| `swift-swiftui` | Model-View patterns — `@Observable` models, enum-based state, model composition, dependency injection |

## Background

ClaudeChain is an automated PR creation system that processes tasks from a `spec.md` file in a repo's `claude-chain/` directory. The SDK, Service, and Feature layers already exist (`ClaudeChainSDK`, `ClaudeChainService`, `ClaudeChainFeature`) with project discovery, task management, and PR operations. The CLI (`ClaudeChainCLI`) is also wired up.

The Mac app (`AIDevToolsKitMac`) currently supports selecting repositories and navigating to features like Evals, Architecture Planner, Plans, and Skills. We want to add ClaudeChain as another feature in that sidebar. The user selects a repo, taps "Claude Chain", sees available chains (projects), selects one, and can run it.

This plan covers:
1. Two new use cases in the Features layer: list chains and execute a chain
2. A new `@Observable` model in the Apps layer
3. New SwiftUI views wired into the existing `WorkspaceView`
4. CLI verification using the `../claude-chain-demo` repo

Key constraint: `Project.findAll(baseDir:)` currently uses a relative path. For the Mac app, we need to pass the absolute path to the selected repo's `claude-chain/` directory. The existing `RepositoryInfo.path` provides the repo root URL.

The existing ClaudeChain Feature layer has services (`PRService`, `TaskService`, etc.) that take a `repo` string (GitHub `owner/repo` format) and call `gh` CLI. For local execution from the Mac app, we primarily need `Project.findAll()` for discovery (filesystem-based) and a local claude-code invocation for execution (similar to how `MarkdownPlannerModel` calls `ExecutePlanUseCase` which runs an AI client).

## Phases

## - [x] Phase 1: Create Use Cases in ClaudeChainFeature

**Skills used**: `swift-architecture` (creating-features.md)
**Principles applied**: Use cases are Sendable structs following existing codebase patterns (no formal UseCase protocol). ListChainsUseCase creates absolute-path Project instances so `ProjectRepository.loadLocalSpec` resolves files correctly. ExecuteChainUseCase shells out to `claude` CLI directly via Process with `currentDirectoryURL` set to the repo path, keeping the first pass simple as specified.

**Skills to read**: `swift-architecture` (creating-features.md)

Create two use cases in `Sources/Features/ClaudeChainFeature/usecases/`:

### ListChainsUseCase

A `UseCase` that discovers ClaudeChain projects for a given repository path.

- **Options**: repo path (`URL`)
- **Result**: `[ChainProject]` — a lightweight struct with project name, spec path, task counts (total, completed, pending)
- Uses `Project.findAll(baseDir:)` with the repo's `claude-chain/` directory
- For each discovered project, loads the spec via `ProjectRepository.loadLocalSpec(project:)` to get task counts
- Note: `Project.findAll` currently takes a relative `baseDir` string. We need to `chdir` or pass the absolute path `repoPath/claude-chain`. Check if `findAll` works with absolute paths — it uses `FileManager.contentsOfDirectory(atPath:)` so it should.

### ExecuteChainUseCase

A `UseCase` (or `StreamingUseCase` if progress reporting is desired) that executes the next available task for a given chain project on a repo.

- **Options**: repo path (`URL`), project name (`String`)
- **Result**: execution outcome (success with PR URL, or description of what happened)
- Steps:
  1. Load the spec locally via `ProjectRepository.loadLocalSpec`
  2. Find the next available task via `SpecContent.getNextAvailableTask`
  3. Create a branch using `GitOperations.runGitCommand`
  4. Build the Claude prompt (same as `PrepareCommand` step 6)
  5. Invoke Claude Code via the existing `ClaudeProvider` (from `ClaudeCLISDK`) to execute the task — this is the same AI client the plan runner uses
  6. After Claude completes, create a PR using `gh pr create` via `GitHubOperations` or `GitOperations.runCommand`
- This is the most complex piece. For the first pass, keep it simple: run claude-code CLI directly via `Process`/`GitOperations.runCommand` in the repo directory, since that's closest to what the GitHub Actions workflow does.

### Package.swift changes

No new target needed — these use cases go into the existing `ClaudeChainFeature` target. However, `ClaudeChainFeature` may need a dependency on `ClaudeCLISDK` if we use `ClaudeProvider` for execution. Evaluate whether to use `ClaudeProvider` or just shell out to `claude` CLI directly. Shelling out is simpler for the first pass.

## - [x] Phase 2: Create ClaudeChainModel in Apps Layer

**Skills used**: `swift-swiftui` (model-state.md, model-composition.md)
**Principles applied**: Enum-based state with five cases matching the spec. Injected use cases via constructor with defaults. Async task management in `loadChains` and `executeChain` methods following MarkdownPlannerModel patterns. Added `ClaudeChainFeature` to Package.swift dependencies (pulled forward from Phase 4 since the model needs it to compile).

**Skills to read**: `swift-swiftui` (model-state.md, model-composition.md)

Create `Sources/Apps/AIDevToolsKitMac/Models/ClaudeChainModel.swift`:

- `@MainActor @Observable final class ClaudeChainModel`
- Enum-based state:
  ```
  enum State {
      case idle
      case loadingChains
      case loaded([ChainProject])
      case executing(projectName: String, status: String)
      case error(Error)
  }
  ```
- Injected use cases: `ListChainsUseCase`, `ExecuteChainUseCase`
- Methods:
  - `loadChains(for repoPath: URL)` — calls `ListChainsUseCase`, updates state
  - `executeChain(projectName: String, repoPath: URL)` — calls `ExecuteChainUseCase`, updates state
- Follow the same patterns as `MarkdownPlannerModel` for async task management

## - [x] Phase 3: Create ClaudeChainView and Wire into WorkspaceView

**Skills used**: `swift-swiftui` (dependency-injection.md, view-state.md)
**Principles applied**: Selection state (`selectedProject`) owned by the view via `@State` per view-state.md conventions. ClaudeChainModel injected via `@Environment` following dependency-injection.md patterns. Sidebar sections ordered alphabetically (Claude Chain before Evals). AppStorage persistence follows existing pattern with a `storedClaudeChain` bool. Simplified onChange handler by resetting all stored values first then setting the active one.

**Skills to read**: `swift-swiftui` (dependency-injection.md, view-state.md)

### Update WorkspaceItem enum

Add `case claudeChain` to `WorkspaceItem` in `WorkspaceView.swift`.

### Add sidebar section

In `WorkspaceView`'s `List(selection:)` builder, add a "Claude Chain" section (alphabetically placed before "Evals"):

```swift
Section("Claude Chain") {
    Text("Claude Chain")
        .tag(WorkspaceItem.claudeChain)
}
```

### Create ClaudeChainView

Create `Sources/Apps/AIDevToolsKitMac/Views/ClaudeChainView.swift`:

- Reads `@Environment(ClaudeChainModel.self)`
- Shows a list of discovered chain projects (from model state)
- Each row shows: project name, task progress (e.g., "3/5 tasks completed")
- Selecting a project shows a detail panel with:
  - Project name and spec path
  - Task list (completed vs pending)
  - "Run Next Task" button that calls `model.executeChain(...)`
  - Execution status while running

### Wire detail view

In `WorkspaceView`'s `detailContentView` switch, add:
```swift
case .claudeChain:
    ClaudeChainView(repository: repo)
```

### Load chains on repo selection

In `WorkspaceView`'s `onChange(of: selectedItem)` or `onChange(of: selectedRepoID)`, call `claudeChainModel.loadChains(for: repo.path)` when the Claude Chain item is selected (or eagerly when repo is selected).

## - [x] Phase 4: Wire ClaudeChainModel into App Entry Point

**Skills used**: `swift-swiftui` (dependency-injection.md)
**Principles applied**: Root model stored as `@State` in the app entry view per DI skill conventions. Environment injection follows alphabetical ordering alongside existing models. ClaudeChainModel uses default use case initializers (no CompositionRoot wiring needed). Added `ClaudeChainService` to Package.swift dependencies alphabetically.

**Skills to read**: `swift-swiftui` (dependency-injection.md)

### Update AIDevToolsKitMacEntryView

1. Add `@State private var claudeChainModel: ClaudeChainModel` property
2. Initialize in `init()` with `ClaudeChainModel(listChainsUseCase:executeChainUseCase:)`
3. Add `.environment(claudeChainModel)` to the view hierarchy

### Update Package.swift

Add `ClaudeChainFeature` and `ClaudeChainService` to the `AIDevToolsKitMac` target's dependencies list (alphabetically ordered).

## - [x] Phase 5: Verify CLI Execution with claude-chain-demo

**Skills used**: none
**Principles applied**: Verified full end-to-end chain execution against `claude-chain-demo` repo. Ran `claude-chain prepare` CLI with `GITHUB_REPOSITORY=gestrich/claude-chain-demo PROJECT_NAME=hello-world` — discovered project, checked capacity, found task 5 ("Create hello-world-5.txt"), created branch `claude-chain-hello-world-144f047c`. Then ran `claude -p` with the prepared prompt and `--dangerously-skip-permissions` — Claude created and committed `hello-world-5.txt`. Pushed branch and created draft PR gestrich/claude-chain-demo#88. Required `gh auth switch --user gestrich` for repo access. Label creation error is non-blocking (label already existed). Previous runs' branches/PRs needed cleanup before retry.

**Skills to read**: none (manual verification)

This phase verifies that the underlying chain execution works end-to-end using the demo repo at `../claude-chain-demo`.

### Steps

1. Navigate to the `claude-chain-demo` repo
2. Run `Project.findAll()` equivalent — verify the `hello-world` and `async-test` chains are discovered
3. For the `hello-world` chain, verify that `spec.md` shows task 5 ("Create hello-world-5.txt") as the next available task
4. Execute the chain locally:
   - Create a branch: `claude-chain-hello-world-<hash>`
   - Run claude-code with the task prompt in the demo repo directory
   - Verify a PR is created on the demo repo
5. This can be done via the CLI entry point or by writing a small test script that calls the use cases directly

### What to verify
- Chain discovery works with absolute paths
- Spec parsing correctly identifies completed vs pending tasks
- Branch creation succeeds
- Claude executes the task and creates the expected file
- A PR is created on the remote

If execution fails, debug and fix before proceeding. This is the first time running claude-chain locally (outside GitHub Actions), so expect potential issues with environment assumptions (e.g., `GITHUB_REPOSITORY` env var, `gh` auth).

## - [x] Phase 6: Validation

**Skills used**: `swift-testing`
**Principles applied**: Created `AIDevToolsKitMacTests` test target for the Mac app layer. Tests cover ClaudeChainModel state machine transitions (idle, loadingChains, loaded, executing, error) using temp directories with real spec.md files rather than mocks. Follows Arrange-Act-Assert pattern with `@Test` and `#expect` per swift-testing skill. Full package `swift build` verified. All 7 model tests pass alongside the 9 existing use case tests from Phase 5.

**Skills to read**: `swift-testing`

### Build verification
- Verify `AIDevToolsKitMac` target compiles with the new `ClaudeChainFeature` dependency
- Verify `ClaudeChainFeature` target compiles with new use cases
- Run `swift build` for the full package

### Unit tests
- Test `ListChainsUseCase` with a mock filesystem (or use the demo repo path)
- Test `ClaudeChainModel` state transitions: idle -> loading -> loaded, idle -> executing -> completed/error

### Integration verification
- Launch the Mac app
- Select a repository that contains a `claude-chain/` directory
- Verify "Claude Chain" appears in the sidebar
- Verify clicking it shows the list of chains
- Verify selecting a chain shows task details and a run button
- (Optional) Verify running a chain from the UI creates a PR on the demo repo
