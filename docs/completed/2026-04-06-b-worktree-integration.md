## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | Checks and fixes 4-layer architecture violations (layer placement, upward deps, observable conventions, use case struct rules) |
| `ai-dev-tools-enforce` | Runs enforcement of all coding standards after changes complete |
| `ai-dev-tools-swift-testing` | Test style guide and conventions for Swift Testing framework |
| `swift-architecture` | Architecture reference for planning new features in the 4-layer system |

## Background

The goal is to bring git worktree management into the AIDevTools Mac app by migrating the proven worktree support from `RefactorApp` (`/Users/bill/Developer/personal/RefactorApp`) into our own stack. We do **not** import or depend on RefactorApp code — we adapt the patterns into our existing `GitSDK`, add a new `WorktreeFeature`, and surface a new **Worktrees** tab in the Mac app's per-repository workspace.

### What already exists in AIDevTools

- `SDKs/GitSDK/GitCLI.swift` — `GitCLI.Worktree.Add`, `.Remove`, `.Prune` structs already defined; **missing**: `Worktree.List`
- `SDKs/GitSDK/GitClient.swift` — `createWorktree`, `removeWorktree`, `pruneWorktrees` already exist; **missing**: `listWorktrees`
- `SDKs/GitSDK/GitOperationsService.swift` — high-level git operations; no worktree methods yet
- `Apps/AIDevToolsKitMac/Views/WorkspaceView.swift` — `TabView` with 6 tabs; the "Worktrees" tab needs to be added
- `Apps/AIDevToolsKitMac/Models/WorkspaceModel.swift` — holds `selectedRepository: RepositoryConfiguration?`

### What we're adding

1. A `Worktree.List` git command + `WorktreeInfo` model in `GitSDK`
2. A `listWorktrees` method on `GitClient`
3. A new `WorktreeFeature` target with three use cases and CLI parity
4. A `WorktreeModel` + `WorktreesView` + `AddWorktreeSheet` in the Mac Apps layer
5. A "Worktrees" tab wired into `WorkspaceView`

### Reference source (RefactorApp)

Patterns to adapt (do not copy wholesale):
- `sdks/GitClient/Sources/GitClient/CommandBuilder.swift` — worktree command building
- `services/GitService/Sources/GitService/WorktreeService.swift` — listing + parsing
- `services/GitService/Sources/GitService/Models/WorktreeInfo.swift` — model shape
- `sdks/GitClient/Sources/GitClient/Models/WorktreeState.swift` — state detail

---

## Phases

## - [x] Phase 1: Extend GitSDK — List command, WorktreeInfo model, listWorktrees method

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Added `GitCLI.Worktree.List` in alphabetical order within the `Worktree` namespace. `WorktreeInfo` is a pure `Sendable` struct with only what `git worktree list --porcelain` provides (no dirty-state — that's Feature-layer orchestration). `listWorktrees` makes exactly one CLI call; parsing extracted into a private helper to keep the public method clean.

**Skills to read**: `ai-dev-tools-architecture` (SDKs layer rules)

### `GitCLI.Worktree.List` — `GitCLI.swift`

Add a `List` subcommand to the existing `GitCLI.Worktree` namespace:

```swift
@CLICommand
public struct List {
    @Flag("--porcelain") public var porcelain: Bool = false
}
```

Keep alphabetical order within `GitCLI.Worktree`.

### `WorktreeInfo` model — new file `SDKs/GitSDK/WorktreeInfo.swift`

```swift
public struct WorktreeInfo: Identifiable, Sendable {
    public let id: UUID
    public let path: String
    public let branch: String   // e.g. "main", "feature/foo", "(detached)"
    public let isMain: Bool     // true for the primary worktree

    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}
```

**No `hasUncommittedChanges` here.** The architecture skill requires each SDK method to wrap exactly one CLI command. Checking dirty state would require a separate `git status` call per worktree — that's N+1 commands in one SDK method, which is orchestration and belongs in the Feature layer. `WorktreeInfo` only contains what `git worktree list --porcelain` directly provides.

### `listWorktrees` — `GitClient.swift`

Add alongside the existing `createWorktree`, `removeWorktree`, `pruneWorktrees`:

```swift
public func listWorktrees(workingDirectory: String) async throws -> [WorktreeInfo]
```

Parse `git worktree list --porcelain` output. Each block looks like:

```
worktree /path/to/repo
HEAD abc123...
branch refs/heads/main

worktree /path/to-worktree
HEAD def456...
branch refs/heads/feature/foo
```

Parse blocks separated by blank lines. Detect the main worktree as the first entry (it always comes first in porcelain output). Strip `refs/heads/` prefix from branch names. Handle `detached` keyword for detached HEAD state. This is a single `git worktree list --porcelain` call — no additional per-worktree commands.

---

## - [x] Phase 2: WorktreeFeature — Use cases, Package.swift, CLI parity

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Three use cases as plain `UseCase` structs taking `GitClient` via `init`. `ListWorktreesUseCase` does the Feature-layer orchestration (sequential `isWorkingDirectoryClean` per worktree) that belongs above the SDK. `WorktreeError` wraps failures at the Feature boundary with `LocalizedError`. `GitClient.removeWorktree` gained a `force: Bool = true` parameter (backward-compatible) so the use case can honor the caller's intent. CLI subcommands (add/list/remove) follow the existing `AsyncParsableCommand` pattern; `WorktreeCommand` registered alphabetically in `EntryPoint`. `WorktreeFeature` product and target added to `Package.swift` with dependencies sorted alphabetically.

**Skills to read**: `ai-dev-tools-architecture` (Features layer rules)

### New target directory

Create `AIDevToolsKit/Sources/Features/WorktreeFeature/UseCases/` with three use case files.

### `WorktreeStatus` model — new file `WorktreeFeature/Models/WorktreeStatus.swift`

`WorktreeInfo` (SDK layer) only carries what `git worktree list --porcelain` gives us. Dirty-state awareness requires a `git status` call per worktree — that's Feature-layer orchestration. Define a Feature-layer enriched model:

```swift
public struct WorktreeStatus: Identifiable, Sendable {
    public let info: WorktreeInfo
    public let hasUncommittedChanges: Bool

    public var id: UUID { info.id }
    public var name: String { info.name }
    public var branch: String { info.branch }
    public var isMain: Bool { info.isMain }
    public var path: String { info.path }
}
```

### `WorktreeError` — new file `WorktreeFeature/WorktreeError.swift`

Define errors at the Feature layer (not in `GitOperationsService`, which the worktree flow doesn't use):

```swift
public enum WorktreeError: LocalizedError {
    case listFailed(String)
    case addFailed(String)
    case removeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .listFailed(let detail): "Failed to list worktrees: \(detail)"
        case .addFailed(let detail): "Failed to add worktree: \(detail)"
        case .removeFailed(let detail): "Failed to remove worktree: \(detail)"
        }
    }
}
```

### Use cases

Each is a `public struct` conforming to `UseCase` (check the existing `UseCaseSDK` for the protocol). All take `GitClient` via `init`:

**`ListWorktreesUseCase.swift`**

Calls `gitClient.listWorktrees` then enriches each with a `gitClient.isWorkingDirectoryClean` call — this multi-step orchestration is correct at the Feature layer. Returns `[WorktreeStatus]`.

```swift
public struct ListWorktreesUseCase {
    private let gitClient: GitClient
    public init(gitClient: GitClient) { ... }
    public func execute(repoPath: String) async throws -> [WorktreeStatus]
}
```

**`AddWorktreeUseCase.swift`**
```swift
public struct AddWorktreeUseCase {
    private let gitClient: GitClient
    public init(gitClient: GitClient) { ... }
    public func execute(repoPath: String, destination: String, branch: String) async throws
}
```

**`RemoveWorktreeUseCase.swift`**
```swift
public struct RemoveWorktreeUseCase {
    private let gitClient: GitClient
    public init(gitClient: GitClient) { ... }
    public func execute(repoPath: String, worktreePath: String, force: Bool) async throws
}
```

### `Package.swift` — add WorktreeFeature target

```swift
.library(name: "WorktreeFeature", targets: ["WorktreeFeature"]),
```

```swift
.target(
    name: "WorktreeFeature",
    dependencies: ["GitSDK"],
    path: "Sources/Features/WorktreeFeature"
),
```

Keep both lists alphabetically sorted.

### CLI parity — `AIDevToolsKitCLI`

Add a `WorktreeCommand` as a subcommand group with:
- `worktree list <repo-path>` → `ListWorktreesUseCase`
- `worktree add <repo-path> <destination> --branch <name>` → `AddWorktreeUseCase`
- `worktree remove <repo-path> <worktree-path> [--force]` → `RemoveWorktreeUseCase`

Register `WorktreeCommand` in the CLI's main command group. Add `WorktreeFeature` to `AIDevToolsKitCLI`'s dependencies in `Package.swift`.

---

## - [x] Phase 3: Apps Layer — WorktreeModel, WorktreesView, tab

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: `WorktreeModel` uses enum-based state with `prior` pattern to retain last-known data across reloads. `UseCases` private struct groups all three use cases into one init-time assignment. Model created once in the entry view and injected via SwiftUI environment; `WorkspaceModel` holds an optional `WorktreeModel?` reference (nil in settings view) and fires `load` as a detached `Task` in `selectRepository(_:)` so worktree refresh runs in parallel with skill loading. `import Observation` added explicitly since `WorktreeModel` doesn't import SwiftUI directly.

**Skills to read**: `ai-dev-tools-architecture` (Apps layer rules)

### `WorktreeModel.swift`

`@Observable @MainActor final class WorktreeModel` — follows the exact same enum-based state pattern as other models in the codebase:

```swift
@Observable @MainActor final class WorktreeModel {
    enum State {
        case idle
        case loading(prior: [WorktreeStatus]?)
        case loaded([WorktreeStatus])
        case error(Error, prior: [WorktreeStatus]?)
    }

    private(set) var state: State = .idle

    private struct UseCases {
        let list: ListWorktreesUseCase
        let add: AddWorktreeUseCase
        let remove: RemoveWorktreeUseCase
        init(gitClient: GitClient) { ... }
    }
    private let useCases: UseCases

    init(gitClient: GitClient) { ... }

    func load(repoPath: String) async { ... }
    func addWorktree(repoPath: String, destination: String, branch: String) async { ... }
    func removeWorktree(repoPath: String, worktreePath: String) async { ... }
}
```

- `load` transitions to `.loading(prior:)`, then `.loaded` or `.error`
- `addWorktree` and `removeWorktree` call their use cases, then reload
- All `catch` blocks set `.error(error, prior:)` — never swallow

**Wiring into `CompositionRoot` and the environment:**

`WorktreeModel` is created once in `CompositionRoot` (using the same `CLIClient` as other git operations) and injected into the SwiftUI environment alongside `WorkspaceModel` and `AppModel`. It is **not** re-created per repo. Instead, `WorkspaceModel.selectRepository(_:)` calls `worktreeModel.load(repoPath:)` so the model refreshes whenever the selected repo changes. `WorktreesView` reads it from `@Environment(WorktreeModel.self)` — no passing through `WorkspaceView`.

### `WorktreesView.swift`

Primary list view. Receives `WorktreeModel` via `@Environment(WorktreeModel.self)`:

- Shows a `List` of `WorktreeStatus` items (use `WorktreeRowView`)
- Toolbar button: "Add Worktree" → presents `AddWorktreeSheet`
- Each row has a context menu / swipe actions: **Open in Finder**, **Open in Terminal**, **Remove**
- Loading state shows `ProgressView`; error state shows `ContentUnavailableView` with the error message

### `WorktreeRowView.swift`

Row item displaying:
- Worktree `name` (last path component)
- Branch name
- Orange dot indicator when `hasUncommittedChanges == true`
- "Main" badge on the primary worktree

### `AddWorktreeSheet.swift`

Sheet with:
- `destination` text field (path for new worktree directory)
- `branch` text field (branch name to create/checkout)
- Cancel / Add buttons
- On submit: calls `model.addWorktree(repoPath:destination:branch:)` and dismisses

### Wire the tab — `WorkspaceView.swift`

Add to `tabContent(for:)`:

```swift
WorktreesView()
    .tabItem { Label("Worktrees", systemImage: "square.split.2x1") }
    .tag("worktrees")
```

`WorktreesView` reads `WorktreeModel` from `@Environment` (injected at the app root, not passed here). The repo-change trigger goes in `WorkspaceModel.selectRepository(_:)`, not in `WorkspaceView` — keep view logic minimal.

Also add `WorktreeFeature` to `AIDevToolsKitMac`'s dependencies in `Package.swift`.

---

## - [x] Phase 4: Validation

**Skills used**: `ai-dev-tools-swift-testing`, `ai-dev-tools-enforce`
**Principles applied**: Fixed error swallowing in `ListWorktreesUseCase` — replaced `try?` on `isWorkingDirectoryClean` with explicit `do/catch` that throws `WorktreeError.listFailed`, per the architecture skill's rule that Features must propagate errors. Added `worktreeListArguments` command test and three `listWorktrees` integration tests (main worktree, multiple worktrees, detached HEAD) to `GitClientTests`. Created `WorktreeFeatureTests` with 13 tests covering `WorktreeError` descriptions, `WorktreeStatus` property proxying, and all three use cases including error paths. Used POSIX `realpath()` to canonicalize temp paths so they match git's `/private/var/...` resolved paths on macOS.

**Skills to read**: `ai-dev-tools-swift-testing`, `ai-dev-tools-enforce`

### Enforcement

Run `ai-dev-tools-enforce` on all new and modified files:
- `GitCLI.swift`, `GitClient.swift`, `WorktreeInfo.swift`, `GitOperationsService.swift`
- All three use case files in `WorktreeFeature`
- `WorktreeModel.swift`, `WorktreesView.swift`, `AddWorktreeSheet.swift`, `WorktreeRowView.swift`
- `WorkspaceView.swift`, `CompositionRoot.swift`, `Package.swift`

### Unit tests — `WorktreeFeature`

Create `WorktreeFeatureTests/` with tests for each use case. Use mock `GitClient` (or a real one pointed at a temp repo). Follow `ai-dev-tools-swift-testing` conventions (Swift Testing `@Test` macros, not XCTest).

Key test cases:
- `ListWorktreesUseCase` returns correct `WorktreeStatus` array (with `hasUncommittedChanges`) for a repo with multiple worktrees
- `AddWorktreeUseCase` creates the worktree directory
- `RemoveWorktreeUseCase` removes worktree with and without `--force`
- `GitClient.listWorktrees` parsing handles the main worktree, detached HEAD, and missing branch fields

### Manual smoke test

1. Select a repository in the Mac app
2. Navigate to the Worktrees tab — confirm the list loads
3. Add a worktree — confirm it appears in the list
4. Open in Finder / Terminal — confirm correct path
5. Remove a worktree — confirm it disappears from the list
6. Run `ai-dev-tools-kit worktree list <path>` in the CLI — confirm matching output
