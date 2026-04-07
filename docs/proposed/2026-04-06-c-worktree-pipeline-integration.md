## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture guidance (Apps, Features, Services, SDKs) |
| `ai-dev-tools-architecture` | Checks for layer violations, dependency direction, orchestration placement |
| `ai-dev-tools-code-quality` | Force unwraps, raw strings, duplicated logic |
| `ai-dev-tools-swift-testing` | Test style guide and Swift Testing conventions |
| `ai-dev-tools-enforce` | Post-change verification of all coding standards |

## Background

We want worktree support to be a first-class, reusable capability across features — specifically ClaudeChain and Planning — with room to add it to future features without boilerplate.

The key insight is that **worktree creation maps naturally to a `PipelineNode`**. Both ClaudeChain and Planning already build `PipelineBlueprint` objects and run them through `PipelineRunner`. A `WorktreeNode` placed at the front of the node array creates the worktree and writes the new working directory into `PipelineContext.workingDirectoryKey`, so all subsequent nodes (AI tasks, PR steps, etc.) automatically operate in the isolated worktree.

**Worktree path structure** (rooted at the app's configured data directory):

```
<dataDir>/<featureName>/worktrees/<identifier>
```

- `dataDir` comes from `AppPreferences` / `SettingsModel` (already injected into `ClaudeChainModel` via `DataPathsService`)
- `featureName` is the kebab-case feature name — keeping each feature's data together (e.g. `claude-chain`, `plan`). This also sets the convention for future feature-specific data beyond worktrees.
- `identifier` is a unique, traceable name tied to the task or plan:
  - ClaudeChain: reuse the existing branch name (`claude-chain-<project>-<8-hex>`) — the same identifier used for the Git branch
  - Plan: `plan-<8-hex-of-plan-filename>` — hashed from the plan document's filename stem

**Why a new `ServicePath` case?** `DataPathsService` already manages all feature-specific subdirectories through typed `ServicePath` cases. Adding `.worktrees(feature:)` keeps the path logic in one authoritative place and lets each feature scope its own data directory. The feature name string (e.g. `"claude-chain"`) is passed by the caller, making it trivial to add worktree support to a future feature without touching `ServicePath`.

**Identifier/hash for plans**: `TaskService.generateTaskHash(description:)` (in `ClaudeChainService`) computes a stable 8-char hex hash from any string. We can extract that logic — or replicate the one-liner — to generate the plan worktree identifier from the plan filename stem.

**Module placement**: `WorktreeNode` belongs in `PipelineService` (not `PipelineSDK` and not a feature). `PRStep` and `CodeChangeStepHandler` establish this precedent — nodes with `GitSDK` or service dependencies live in `PipelineService`. `WorktreeFeature` must NOT be imported from `PipelineService` (services cannot depend on features); instead, `WorktreeNode` calls `gitClient.createWorktree(...)` directly.

**`WorktreeOptions`**: A small value type in `PipelineService` that bundles `repoPath`, `destinationPath`, and `branchName`. Both `ChainRunOptions` and `PlanService.ExecuteOptions` will carry an optional `WorktreeOptions`. If non-nil, the respective pipeline-builder prepends a `WorktreeNode`. Adding worktree support to a future feature is then just: (1) add `worktreeOptions: WorktreeOptions?` to its options type, and (2) prepend the node.

## Phases

## - [x] Phase 1: Core infrastructure — `WorktreeOptions`, `WorktreeNode`, `ServicePath`

**Skills used**: `swift-architecture`, `ai-dev-tools-architecture`
**Principles applied**: `WorktreeNode` placed in `PipelineService` (same layer as `PRStep`), not in a feature or SDK. `WorktreeOptions` is a plain `Sendable` value type. `ServicePath.worktrees` case inserted in alphabetical order. Static `worktreePathKey` follows the `PRStep.prURLKey` pattern.

**Skills to read**: `swift-architecture`, `ai-dev-tools-architecture`

Add the two building blocks that all features will share.

**`ServicePath`** (`DataPathsService/ServicePath.swift`):
- Add case `.worktrees(feature: String)` with `relativePath` = `"\(feature)/worktrees"`
- Example: `.worktrees(feature: "claude-chain")` → `<dataDir>/claude-chain/worktrees`
- Keep enum cases sorted alphabetically

**`WorktreeOptions`** (new file `PipelineService/WorktreeOptions.swift`):
```swift
public struct WorktreeOptions: Sendable {
    public let branchName: String
    public let destinationPath: String
    public let repoPath: String

    public init(branchName: String, destinationPath: String, repoPath: String) { ... }
}
```

**`WorktreeNode`** (new file `PipelineService/WorktreeNode.swift`):
- Conforms to `PipelineNode`
- `id`: `"worktree-node"`, `displayName`: `"Creating worktree"`
- `init(options: WorktreeOptions, gitClient: GitClient)`
- `run(context:onProgress:)`:
  1. `onProgress(.output("Creating worktree at \(options.destinationPath)..."))`
  2. `try await gitClient.createWorktree(baseBranch: options.branchName, destination: options.destinationPath, workingDirectory: options.repoPath)`
  3. Set `context[PipelineContext.workingDirectoryKey] = options.destinationPath`
  4. Set `context[WorktreeNode.worktreePathKey] = options.destinationPath`
  5. Return updated context
- Define `static let worktreePathKey = PipelineContextKey<String>("WorktreeNode.worktreePath")` on the struct (same pattern as `PRStep.prURLKey`)

No new `Package.swift` dependencies needed — `PipelineService` already imports `GitSDK`.

## - [x] Phase 2: ClaudeChainFeature integration

**Skills used**: `swift-architecture`
**Principles applied**: All worktree logic added to `ClaudeChainService.buildPipeline` and `buildFinalizePipeline` — no changes needed in the use case wrappers since the service already owns `self.git`. `worktreeOptions` added to `ChainRunOptions` in alphabetical order, defaulting to `nil` for backward compatibility.

Wire `WorktreeOptions` into the ClaudeChain execution pipeline.

**`ChainRunOptions`** (`ClaudeChainFeature/ClaudeChainService.swift`):
- Add `public let worktreeOptions: WorktreeOptions?` (default `nil`)
- Add to `init` with default `nil`
- Keep stored properties sorted alphabetically

**`BuildTaskPipelineUseCase`** (`ClaudeChainFeature/usecases/BuildTaskPipelineUseCase.swift`):
- Accept a `GitClient` (already available via `ClaudeChainService`) or pass one in at init
- When `options.worktreeOptions != nil`, prepend `WorktreeNode(options:gitClient:)` to the blueprint's nodes array
- The `WorktreeNode` overrides `workingDirectoryKey` in context, so the AI task and `PRStep` that follow automatically run in the worktree

**`BuildFinalizePipelineUseCase`** (`ClaudeChainFeature/usecases/BuildFinalizePipelineUseCase.swift`):
- Same change: prepend `WorktreeNode` when `options.worktreeOptions != nil`
- The finalise pipeline (PR creation) should also operate in the worktree branch

`ClaudeChainFeature` already declares `PipelineService` as a dependency in `Package.swift` — no change needed there.

## - [x] Phase 3: PlanFeature integration

**Skills used**: `swift-architecture`
**Principles applied**: Added `PipelineService` dependency to `PlanFeature` in `Package.swift`. Replaced dead `useWorktree: Bool` with `worktreeOptions: WorktreeOptions?` in both `PlanService.ExecuteOptions` and `ExecutePlanUseCase.Options`. Updated `buildExecutePipeline` to prepend `WorktreeNode` when `worktreeOptions` is non-nil, matching the ClaudeChain pattern.

**Skills to read**: `swift-architecture`

Wire `WorktreeOptions` into plan execution.

**`Package.swift`**:
- Add `"PipelineService"` to `PlanFeature`'s dependencies array (currently only has `PipelineSDK`)

**`PlanService.ExecuteOptions`** (`PlanFeature/PlanService.swift`):
- Replace the dead `useWorktree: Bool` field with `worktreeOptions: WorktreeOptions?` (default `nil`)
- Update callers: `PlanModel.execute()` passes `nil` for now (UI comes in Phase 4)
- Remove `useWorktree` from `ExecutePlanUseCase.Options` as well (deprecated use case; update to remove the dead field)

**`PlanService.buildExecutePipeline()`**:
- When `options.worktreeOptions != nil`, prepend `WorktreeNode` to the blueprint's nodes before `taskSourceNode`:
  ```swift
  var nodes: [any PipelineNode] = []
  if let wo = options.worktreeOptions {
      nodes.append(WorktreeNode(options: wo, gitClient: GitClient()))
  }
  nodes.append(taskSourceNode)
  ```
- The `PipelineConfiguration.workingDirectory` still holds the original repo path (as a fallback); the node overrides it in context

## - [ ] Phase 4: Mac App layer — UI toggles with AppStorage

**Skills to read**: `swift-architecture`

Expose `useWorktree` toggles in the views (persisted via `@AppStorage`) and compute `WorktreeOptions` in the models using `DataPathsService`.

**`PlanModel`** (`AIDevToolsKitMac/Models/PlanModel.swift`):
- Inject `DataPathsService` (pass it in `init`, store as `private let`)
- Add `useWorktree: Bool` parameter to `execute(plan:repository:...)` (default `false`)
- In `execute(plan:repository:useWorktree:...)`:
  - If `useWorktree`, compute the worktree identifier: 8-char hex hash of `plan.planURL.deletingPathExtension().lastPathComponent`
  - Compute branch name: `"plan-\(identifier)"`
  - Resolve destination: `dataPathsService.path(for: .worktrees(feature: "plan")).appendingPathComponent(branchName)`
  - Pass `WorktreeOptions(branchName:destinationPath:repoPath:)` in `ExecuteOptions`

**`ClaudeChainModel`** (`AIDevToolsKitMac/Models/ClaudeChainModel.swift`):
- Add `useWorktree: Bool` parameter to `executeChain(project:repoPath:...)` (default `false`)
- In `executeChain(project:repoPath:useWorktree:...)`:
  - If `useWorktree`, use the existing `branchName` (already computed as the ClaudeChain branch) and `dataPathsService` to build `WorktreeOptions`
  - Destination path: `dataPathsService.path(for: .worktrees(feature: "claude-chain")).appendingPathComponent(branchName)`
  - Pass in `ChainRunOptions`

**UI** — `@AppStorage` toggles in each view, matching the pattern of existing toggles like `chainCreatePR` and `planStopAfterArchitectureDiagram`:

`PlanDetailView.swift`:
```swift
@AppStorage("planUseWorktree") private var useWorktree: Bool = false
```
Add `Toggle("Use worktree", isOn: $useWorktree).toggleStyle(.checkbox)` in `headerBar` near the execute button. Pass `useWorktree` to `planModel.execute(...)` in `startExecution()`.

`ChainProjectDetailView` in `ClaudeChainView.swift`:
```swift
@AppStorage("chainUseWorktree") private var useWorktree: Bool = false
```
Add `Toggle("Use worktree", isOn: $useWorktree).toggleStyle(.checkbox).disabled(isExecuting)` near the `Toggle("Create PR", ...)`. Pass `useWorktree` to `model.executeChain(...)` in `startExecution(taskIndex:)`.

**Composition root** — wherever `PlanModel` is constructed (`AIDevToolsKitMacEntryView` or equivalent), pass the shared `DataPathsService` instance.

## - [ ] Phase 5: Validation

**Skills to read**: `ai-dev-tools-swift-testing`

Write tests and run the enforce skill against all changed files.

**Unit tests** (`WorktreeFeatureTests.swift` or a new `PipelineServiceTests`):
- `WorktreeNode` test: mock `GitClient`, verify `createWorktree` is called with correct args and `workingDirectoryKey` is updated in returned context
- `WorktreeOptions` test: verify properties round-trip correctly

**ClaudeChain tests** (`WorktreeFeatureTests.swift` or `ClaudeChainFeatureTests`):
- When `ChainRunOptions.worktreeOptions` is non-nil, `BuildTaskPipelineUseCase` returns a blueprint whose first node is a `WorktreeNode`
- When nil, no `WorktreeNode` is present

**Plan tests**:
- When `ExecuteOptions.worktreeOptions` is non-nil, `PlanService.buildExecutePipeline` returns a blueprint with `WorktreeNode` as the first node
- When nil, `taskSourceNode` is the first node (existing behavior unchanged)

**ServicePath test**:
- `.worktrees(feature: "claude-chain")` resolves to `"claude-chain/worktrees"`
- `.worktrees(feature: "plan")` resolves to `"plan/worktrees"`

After validation, run:
```
/ai-dev-tools-enforce
```
against all files changed across phases 1–4.
