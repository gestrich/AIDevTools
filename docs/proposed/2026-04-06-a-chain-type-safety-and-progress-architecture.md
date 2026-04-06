# Chain Type Safety and Progress Architecture

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | 4-layer rules, layer placement, dependency direction, use case struct convention |
| `ai-dev-tools-code-quality` | Raw strings where typed models should exist, duplicated logic |
| `ai-dev-tools-enforce` | Orchestrates all practice skills post-change |

## Background

After adding sweep chain support, four code smells surfaced:

1. **Stringy kind check** — `if project.kindBadge == "sweep"` in `ClaudeChainModel` is fragile and leaks chain-type knowledge into the Apps layer. The abstraction should route execution without the model knowing the type.
2. **Scattered `setenv("GH_TOKEN", ...)` calls** — Three feature-layer use cases and several CLI commands each resolve and apply the GitHub credential independently as a process-global side effect. The credential should be resolved once and injected as a typed environment into `GitClient`.
3. **Hardcoded phase lists and status strings in the model** — `ClaudeChainModel` contains `sweepBatchProgress()` / `initialProgress()` with hardcoded string IDs, and `handleSweepProgress` maps Progress cases to string literals. These are use-case concerns, not model concerns.
4. **Verbose `ChainProject` re-init in `mergeSweepData`** — Ten-field manual copy in `ClaudeChainService.mergeSweepData` to replace only task-count fields. Should be a dedicated initializer.

Items addressed by these phases:
- Item 1: Protocol-based execution dispatch (Option B) — removes `kindBadge` check from model
- Item 2: Combined Progress display text + PhaseInfo at Features layer
- Item 3: `ChainProject` merging initializer
- Item 4: Skipped (leave `githubAccount: String?` as-is)
- Item 5: `setenv` → injected `GitClient` environment (Option B)

---

## Phases

## - [x] Phase 1: `ChainProject` merging initializer

**Skills used**: `ai-dev-tools-code-quality`, `ai-dev-tools-architecture`
**Principles applied**: Added `init(merging:into:)` convenience initializer to `ChainProject` in the Services layer; replaced the verbose 10-field manual copy in `mergeSweepData` with a single `ChainProject(merging: local, into: remote)` call. No new types or abstraction layers needed — this is a straightforward deduplication per code-quality guidelines.

**Skills to read**: `ai-dev-tools-code-quality`, `ai-dev-tools-architecture`

Add a convenience initializer to `ChainProject` in `ClaudeChainService/ChainModels.swift`:

```swift
public init(merging localTaskData: ChainProject, into remote: ChainProject) {
    self.init(
        name: remote.name,
        specPath: remote.specPath,
        tasks: localTaskData.tasks,
        completedTasks: localTaskData.completedTasks,
        pendingTasks: localTaskData.pendingTasks,
        totalTasks: localTaskData.totalTasks,
        baseBranch: remote.baseBranch,
        isGitHubOnly: remote.isGitHubOnly,
        kindBadge: remote.kindBadge,
        maxOpenPRs: remote.maxOpenPRs
    )
}
```

Update `ClaudeChainService.mergeSweepData` to use it:
```swift
return ChainProject(merging: local, into: remote)
```

**Files**: `ClaudeChainService/ChainModels.swift`, `ClaudeChainFeature/ClaudeChainService.swift`

---

## - [x] Phase 2: `setenv` → injected `GitClient` environment

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-code-quality`
**Principles applied**: Removed `setenv` + `CredentialResolver` from three feature-layer use cases (`ExecuteSweepChainUseCase`, `ExecuteSpecChainUseCase`, `FinalizeStagedTaskUseCase`). Added `git: GitClient = GitClient()` to the two use cases that didn't already have it; the third already had it. Added `makeGitClient()` to `ClaudeChainModel` (Apps layer) which resolves the credential once, calls `setenv` for subprocess inheritance, and returns a `GitClient(environment:)`. Removed the unused `import CredentialService` from `RunSpecChainTaskUseCase`. Added `GitSDK` to `AIDevToolsKitMac` Package.swift dependencies.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-code-quality`

The goal is to remove `setenv("GH_TOKEN", token, 1)` from Feature-layer use cases. Instead, each use case that needs a git client accepts one at init time with the environment already configured. The credential is resolved by the caller (Apps layer or CLI command) before constructing the use case.

**Changes:**

1. **`ExecuteSweepChainUseCase`** — remove `setenv` block; accept `GitClient` in init (defaulting to `GitClient()`); pass it through to `RunSweepBatchUseCase(client:git:)`.

2. **`ExecuteSpecChainUseCase`** (delegates to `RunSpecChainTaskUseCase`) — remove `setenv` block; accept `GitClient` in init; pass to inner use case.

3. **`FinalizeStagedTaskUseCase`** — same pattern.

4. **`ClaudeChainModel`** (Apps layer) — resolve credential once before constructing use cases, create `GitClient(environment: ["GH_TOKEN": token])`, inject into each. Helper method `makeGitClient(credentialAccount:) -> GitClient` to avoid repeating resolution logic.

5. **CLI commands** already configure `GitClient` with environment before passing to use cases — verify they still compile and require no changes.

**Note on Claude subprocess**: The Claude CLI subprocess spawned by `PipelineRunner` reads `GH_TOKEN` from the parent process environment. That side effect cannot be avoided via `GitClient` alone. The `setenv` call must remain for subprocess inheritance — but it moves to exactly one place: the Apps-layer helper that constructs the `GitClient`. Feature use cases become free of it entirely.

**Files**: `ExecuteSweepChainUseCase.swift`, `ExecuteChainUseCase.swift`, `FinalizeStagedTaskUseCase.swift`, `ClaudeChainModel.swift`

---

## - [x] Phase 3: PhaseInfo and PhaseStatus move to Services layer

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Created `ChainExecutionPhase` and `ChainPhaseStatus` in a new `ClaudeChainService/ChainExecutionPhase.swift` (Services layer, accessible to all layers above). Added `static let phases: [ChainExecutionPhase]` to `RunSpecChainTaskUseCase`, `RunSweepBatchUseCase`, and `FinalizeStagedTaskUseCase` so each use case owns its phase list. Updated `ClaudeChainModel` to remove the nested `PhaseInfo`/`PhaseStatus` types and drive the three progress factory methods from the use cases' static `phases` instead of hardcoded arrays. Updated `ClaudeChainView` to reference `ChainPhaseStatus` directly from the Services layer.

**Skills to read**: `ai-dev-tools-architecture`

`PhaseInfo` and `PhaseStatus` are currently nested types inside `ClaudeChainModel` (Apps layer). Because use cases at the Features layer need to declare their own phase lists, these types must move down.

**Move to** `ClaudeChainService/ChainExecutionPhase.swift` (new file in the Services layer):

```swift
public struct ChainExecutionPhase: Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public var status: ChainPhaseStatus
}

public enum ChainPhaseStatus: Sendable {
    case completed, failed, pending, running, skipped
}
```

Each use case gains a static `phases: [ChainExecutionPhase]` property declaring its phase list. `ClaudeChainModel` uses the use case's `phases` instead of its hardcoded `initialProgress()` / `sweepBatchProgress()` methods.

Update `ClaudeChainModel` to reference the new types, renaming `PhaseInfo` → `ChainExecutionPhase` and `PhaseStatus` → `ChainPhaseStatus` at usage sites. Remove the now-dead nested type definitions.

**Files**: New `ClaudeChainService/ChainExecutionPhase.swift`; `ClaudeChainModel.swift`; use cases that declare phase lists.

---

## - [x] Phase 4: Progress cases carry their display text and phase mapping

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-code-quality`
**Principles applied**: Added `displayText: String` and `phaseId: String?` to both `RunSweepBatchUseCase.Progress` and `RunSpecChainTaskUseCase.Progress`. Also added `phaseStatus: ChainPhaseStatus?` to `RunSpecChainTaskUseCase.Progress` to encode the per-case status transition (including conditional `.completed`/`.skipped` for script results). `handleExecutionProgress` in `ClaudeChainModel` collapses to a generic `displayText`/`phaseId`/`phaseStatus` path with two remaining special cases: `preparedTask` (updates task info) and `failed` (marks running phase as failed). `handleSweepProgress` retains a switch for phase status only — no string literals remain in the model — because sweep has double-phase transitions (`.creatingBranch` completes "prepare" AND starts "ai") that can't be expressed as a single `(id, status)` pair.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-code-quality`

Each `Progress` enum (`RunSpecChainTaskUseCase.Progress`, `RunSweepBatchUseCase.Progress`) gains two computed properties:

```swift
var displayText: String { ... }   // human-readable status string
var phaseId: String? { ... }      // which phase this event maps to (nil = no transition)
```

Example for `RunSweepBatchUseCase.Progress`:
```swift
var displayText: String {
    switch self {
    case .checkingOpenPRs:       return "Checking for open PRs..."
    case .creatingBranch(let b): return "Creating branch: \(b)"
    case .runningTasks:          return "Running sweep tasks..."
    case .taskStarted(let id):   return "Processing: \(id)"
    case .taskCompleted(let id): return "Completed: \(id)"
    case .creatingPR:            return "Creating PR..."
    case .prCreated(let url):    return "PR created: \(url)"
    case .completed:             return "Completed"
    }
}
var phaseId: String? {
    switch self {
    case .checkingOpenPRs, .creatingBranch: return "prepare"
    case .runningTasks, .taskStarted, .taskCompleted: return "ai"
    case .creatingPR, .prCreated: return "finalize"
    case .completed: return nil
    }
}
```

`ClaudeChainModel.handleSweepProgress` and `handleExecutionProgress` collapse to:
```swift
current.currentPhase = progress.displayText
if let id = progress.phaseId { current.setPhaseStatus(id: id, status: ...) }
state = .executing(progress: current)
```

The string literals move out of the model and into the Progress types where they belong.

**Files**: `RunSweepBatchUseCase.swift` (SweepFeature), `RunSpecChainTaskUseCase.swift` (ClaudeChainFeature), `ClaudeChainModel.swift`

---

## - [x] Phase 5: Protocol-based execution dispatch — remove `kindBadge` check from model

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Added `ChainKind` enum (`.spec`, `.sweep`) to Services layer (`ChainModels.swift`). Replaced `kindBadge: String?` on `ChainProject`, `ClaudeChainSource`, and all producers/consumers with the typed `kind: ChainKind`. Renamed the existing Features-layer `ChainKind` (which had `.all` for filtering) to `ChainKindFilter` to avoid ambiguity. Created `ChainExecutionStrategy` protocol in `ClaudeChainFeature` with `SpecChainExecutionStrategy` and `SweepChainExecutionStrategy` implementations, plus a `ChainExecutionStrategyFactory` keyed on `ChainKind`. `ClaudeChainModel.executeChain` now calls `ChainExecutionStrategyFactory.strategy(for: project.kind)` — no type check. Removed `executeTask` and `executeSweepBatch` from the model; AI stream events flow through a `StreamAccumulator` in `handleProgressEvent` to deliver content blocks via `executionContentBlocksObserver`.

**Skills to read**: `ai-dev-tools-architecture`

This is the deepest change. The goal: `ClaudeChainModel.executeChain` calls a protocol method without knowing the chain type.

**Approach:**

1. Add `ChainKind` enum to `ClaudeChainService`:
```swift
public enum ChainKind: Sendable {
    case spec, sweep
}
```

2. Replace `kindBadge: String?` on `ChainProject` with `kind: ChainKind` (where current `nil`/`"sweep"` maps to `.spec`/`.sweep`). Update all producers and consumers.

3. Add `executeOptions(for project: ChainProject, repoPath: URL, ...) -> ChainExecuteOptions` to `ClaudeChainSource` protocol (or a parallel `ChainExecutionProvider` protocol in ClaudeChainFeature). Each source returns the typed options needed for its execution path.

4. Alternatively (simpler): add a `func makeExecuteUseCase() -> any ChainExecuteUseCase` to the source, where `ChainExecuteUseCase` is a protocol with `run(options:onProgress:)`. The model calls the protocol; dispatch is inside the source.

5. `ClaudeChainModel.executeChain` becomes:
```swift
func executeChain(project: ChainProject, ...) {
    // No kindBadge check — dispatch lives inside the use case
    let strategy = resolveStrategy(for: project)
    strategy.run(...)
}
```

**Key constraint**: `ClaudeChainSource` lives in the Services layer and cannot import Feature-layer use cases. The execution protocol either lives in Services (accepting only primitive inputs) or in Features (where it can reference use cases directly). The Features approach is cleaner — `ChainExecutionStrategy` protocol lives in `ClaudeChainFeature`, implemented by `SpecChainExecutionStrategy` and `SweepChainExecutionStrategy`, vended by a factory keyed on `ChainKind`.

**Files**: `ClaudeChainService/ChainModels.swift`, `ClaudeChainService/ClaudeChainSource.swift`, new `ClaudeChainFeature/ChainExecutionStrategy.swift`, `ClaudeChainModel.swift`, `SweepClaudeChainSource.swift`, `MarkdownClaudeChainSource.swift`, all consumers of `kindBadge`.

---

## - [x] Phase 6: Enforce all changed files

**Skills used**: `ai-dev-tools-enforce`, `ai-dev-tools-architecture`, `ai-dev-tools-code-quality`, `ai-dev-tools-code-organization`, `ai-dev-tools-build-quality`, `ai-dev-tools-swift-testing`
**Principles applied**: Removed redundant `logger.error` alongside `state = .error(error)` in `ClaudeChainModel.executeChain` (architecture: Apps layer state update is sufficient). Extracted duplicated credential-resolution block from `buildPipeline`/`buildFinalizePipeline` in `ClaudeChainService` into a single private `resolveGitHubEnvironment` helper (code quality: duplicated logic). Moved `SweepBatchStats` public struct from the bottom of `SweepClaudeChainSource.swift` into its own `SweepBatchStats.swift` file (code organization: one file per public type). Fixed `if let _ = try? await` to `if (try? await ...) != nil` in `RunSpecChainTaskUseCase` (idiomatic Swift). Build confirmed clean after all changes.

**Skills to read**: `ai-dev-tools-enforce`

Run `/ai-dev-tools-enforce` on all files modified across Phases 1–5. Fix any violations found before considering the plan complete.

Files expected to be in scope:
- `ChainModels.swift`
- `ChainExecutionPhase.swift` (new)
- `ClaudeChainSource.swift`
- `ClaudeChainService.swift` (feature)
- `ClaudeChainModel.swift`
- `ExecuteSweepChainUseCase.swift`
- `ExecuteChainUseCase.swift`
- `FinalizeStagedTaskUseCase.swift`
- `RunSweepBatchUseCase.swift`
- `RunSpecChainTaskUseCase.swift`
- Any source types that referenced `kindBadge`
