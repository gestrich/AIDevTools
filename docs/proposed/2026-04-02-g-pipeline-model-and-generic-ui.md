## Pipeline Model and Generic UI

**Parent context:** [2026-04-02-b-unify-task-execution-engine.md](2026-04-02-b-unify-task-execution-engine.md), [2026-04-02-e-plans-tab-migration.md](2026-04-02-e-plans-tab-migration.md)

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture — ensures new types land in the right layer |
| `swift-swiftui` | SwiftUI Model-View patterns — `@Observable` model conventions |
| `ai-dev-tools-review` | Reviews Swift files for architecture conformance |

## Background

The Plans tab currently uses `MarkdownPlannerService.execute()` which has its own hand-rolled `while` loop. `PipelineRunner` and `AITask` exist in `PipelineSDK` but `execute()` bypasses them entirely, doing its own phase sequencing, prompt building, and progress reporting.

The goal is:

1. **`PipelineBlueprint`** — a value type returned by feature services (e.g. `MarkdownPlannerService.buildExecutePipeline()`) that describes what to run: nodes + configuration + an upfront node manifest for the UI.
2. **`PipelineModel`** — a generic `@Observable` App-layer model. It accepts a `PipelineBlueprint`, runs it via `PipelineRunner`, and publishes node state for `PipelineView` to bind to. Reused across Plans, Claude Chain, and Architecture tabs.
3. **`PipelineView`** — already exists but is Plans-specific. Make it generic, binding to `PipelineModel`.
4. **`MarkdownPlannerService.buildExecutePipeline()`** — replaces `execute()`. Returns a `PipelineBlueprint`. The service owns prompt enrichment (`instructionBuilder`), credential injection, and `IntegrateTaskIntoPlanUseCase` (moving it out of `MarkdownPlannerModel`).
5. **`MarkdownPlannerModel`** — updated to own a `PipelineModel`, call `buildExecutePipeline()`, and run the blueprint through it. Drops `ExecutionProgress` state and `executionProgressObserver` in favour of `PipelineModel`.

Two-zone UI pattern:
- **Feature-specific list/sidebar** — unchanged, uses feature use cases.
- **Generic pipeline detail** — `PipelineView` bound to `PipelineModel`, knows nothing about Plans/Chain/Architecture.

---

## Phases

## - [x] Phase 1: Extend PipelineSDK with Blueprint and TaskSourceNode

**Skills used**: `swift-architecture`
**Principles applied**: New types (`NodeManifest`, `PipelineBlueprint`, `TaskSourceNode`) added to the SDKs layer as stateless `Sendable` structs. `TaskSourceNode.run()` injects the source into context rather than running tasks directly, letting `PipelineRunner` drain it as designed. `drainTaskSource` uses a peek-ahead pattern to call `betweenTasks` only between tasks (skipping after the last one). Stored properties kept alphabetically per project convention.

**Skills to read**: `swift-architecture`

Add two new types to `PipelineSDK` and update existing ones.

**New: `PipelineBlueprint`**
- `nodes: [any PipelineNode]`
- `configuration: PipelineConfiguration`
- `initialNodeManifest: [NodeManifest]` — pre-known node ids + display names so the UI can show all nodes upfront before any run

**New: `TaskSourceNode: PipelineNode`**
- Wraps `any TaskSource`
- `run()` stores the source in `context[PipelineContext.injectedTaskSourceKey]`
- `PipelineRunner` already checks for this key after each node and drains it — no runner changes needed for basic operation

**Update: `MarkdownTaskSource`**
- Add `instructionBuilder: (@Sendable (PendingTask) -> String)?` init parameter
- In `nextTask()`, if `instructionBuilder` is set, replace `PendingTask.instructions` with its output before returning
- Keeps SDK generic — the enrichment closure carries no Plans knowledge

**Update: `PipelineConfiguration`**
- Add `workingDirectory: String?`
- Add `environment: [String: String]?`
- Add `betweenTasks: (@Sendable () async throws -> Void)?` — called by `PipelineRunner.drainTaskSource()` after each task completes (before the next begins)

**Update: `AITask`**
- Add `workingDirectory: String?` and `environment: [String: String]?` init params
- Pass them into `AIClientOptions` in `run()`

**Update: `PipelineRunner.drainTaskSource()`**
- Pass `configuration.workingDirectory` and `configuration.environment` when constructing `AITask`
- Call `configuration.betweenTasks?()` after `markComplete` and before the next `nextTask()` (skip on last task)

## - [ ] Phase 2: Add `PipelineModel` to the Apps layer

**Skills to read**: `swift-architecture`, `swift-swiftui`

Create `Sources/Apps/AIDevToolsKitMac/Models/PipelineModel.swift`.

```
@MainActor @Observable
final class PipelineModel
```

**State it publishes:**
- `nodes: [NodeState]` — `id`, `displayName`, `isCompleted`, `isCurrent`
- `isRunning: Bool`
- `error: Error?`

**Interface:**
- `func run(blueprint: PipelineBlueprint) async throws`
  - Populates `nodes` from `blueprint.initialNodeManifest` before the runner starts (so the UI shows all nodes upfront)
  - Calls `PipelineRunner.run()`, handling `.nodeStarted` / `.nodeCompleted` / `.nodeProgress` events to update `nodes`
  - Dynamically appends nodes that appear via `.nodeStarted` but weren't in the manifest (e.g. dynamically injected tasks)
- `var onEvent: (@MainActor (PipelineEvent) -> Void)?` — forwarded to `MarkdownPlannerDetailView` so it can feed `ChatMessagesView`
- `func stop()` — cancels the running task

## - [ ] Phase 3: Make PipelineView generic

**Skills to read**: `swift-swiftui`

`PipelineView` currently takes `[PlanPhase]` (Plans-specific). Replace with `@Environment(PipelineModel.self)`.

- Render `pipelineModel.nodes`: each node gets a checkmark (completed), spinner (current), or circle (pending)
- No feature-specific types imported — remove `import MarkdownPlannerFeature`

`MarkdownPlannerDetailView` injects `pipelineModel` via `.environment(pipelineModel)` on `PipelineView`.

## - [ ] Phase 4: Add `buildExecutePipeline()` to `MarkdownPlannerService`

**Skills to read**: `swift-architecture`

Add to `MarkdownPlannerService` (in `MarkdownPlannerFeature` target):

```swift
public func buildExecutePipeline(
    options: ExecuteOptions,
    pendingTasksProvider: (@Sendable () async -> [String])? = nil
) async throws -> PipelineBlueprint
```

**What it does:**
1. Pre-reads phases from the markdown file → builds `initialNodeManifest`
2. Builds `instructionBuilder` closure — enriches raw phase description into the full AI prompt (plan path, phase number, skills-to-read, commit message format, gh instructions). This is the logic currently in `executePhase()`.
3. Resolves credentials → `environment: [String: String]?`
4. If `pendingTasksProvider` is non-nil, builds `betweenTasks` closure that drains it and calls `IntegrateTaskIntoPlanUseCase` — **this moves the integration orchestration out of `MarkdownPlannerModel` and into the service**
5. Creates `MarkdownTaskSource(fileURL:format:instructionBuilder:)`
6. Creates `TaskSourceNode` wrapping the source
7. Returns `PipelineBlueprint(nodes: [taskSourceNode], configuration: config, initialNodeManifest: manifest)`

Remove `execute()`, `executePhase()`, and `betweenPhases` parameter — they are replaced by `buildExecutePipeline()` + `PipelineRunner`.

Keep `generate()` unchanged (it already uses `PipelineRunner` correctly).

## - [ ] Phase 5: Update `MarkdownPlannerModel` to use `PipelineModel`

**Skills to read**: `swift-architecture`, `swift-swiftui`

Replace `ExecutionProgress` + `executionProgressObserver` with an owned `PipelineModel`.

- Add `let pipelineModel = PipelineModel()` as a stored property
- `State` enum: replace `.executing(progress: ExecutionProgress)` with `.executing` (progress is now in `pipelineModel.nodes`)
- `execute()`:
  - Calls `service.buildExecutePipeline(options:pendingTasksProvider:)` passing `{ [weak self] in await MainActor.run { self?.clearQueue().map(\.description) ?? [] } }`
  - Calls `await pipelineModel.run(blueprint:)` — that's the whole execution path
  - On completion: transition state to `.completed` / `.error`
- Remove `IntegrateTaskIntoPlanUseCase` instantiation from `execute()` (now owned by service)
- Remove `betweenPhases` closure from model
- `MarkdownPlannerDetailView` wires `pipelineModel.onEvent` to feed `ChatMessagesView` (replaces `executionProgressObserver`)

## - [ ] Phase 6: Update `MarkdownPlannerDetailView`

**Skills to read**: `swift-swiftui`

- Inject `markdownPlannerModel.pipelineModel` as environment on `PipelineView`
- Replace `executionProgressObserver` callback setup in `startExecution()` with `markdownPlannerModel.pipelineModel.onEvent = { ... }` that feeds `executionChatModel`
- Map `PipelineEvent.nodeStarted` → `appendStatusMessage`, `.nodeProgress(.output)` → stream, `.nodeCompleted` → `finalizeCurrentStreamingMessage`
- `phaseSection`: show `PipelineView` when `pipelineModel.isRunning`, local phase list otherwise
- Header bar phase count reads from `pipelineModel.nodes`

## - [ ] Phase 7: Validation

**Skills to read**: `ai-dev-tools-review`

- Build succeeds
- Generate a plan from the Mac app → confirm it still works
- Execute a plan (next-only mode) → confirm `PipelineView` shows phases, streaming output appears in `ChatMessagesView`
- Execute a plan (all mode) → confirm all phases complete, log files written, plan moves to `completed/`
- Queue a task mid-execution ("Add Task") → confirm it integrates into the plan between phases
- `PipelineView` has no Plans-specific imports
- `MarkdownPlannerModel` has no `executionProgressObserver`, no `ExecutionProgress`, no `betweenPhases`
- `MarkdownPlannerService` has no `execute()`, no `executePhase()`
