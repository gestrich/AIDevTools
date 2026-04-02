## Pipeline Framework

**Parent doc:** [2026-04-02-b-unify-task-execution-engine.md](2026-04-02-b-unify-task-execution-engine.md)

**Goal:** Design and implement the shared `PipelineSDK` — the composable node framework that all three tabs (Architecture, Plans, Claude Chain) will use. This plan makes no changes to any existing feature. When complete, `PipelineSDK` compiles and is unit-tested but is not wired into anything.

**Prerequisites:** None. This is the first plan.

**Read for context:** Read all related documents before working on this plan: [b-unify-task-execution-engine.md](2026-04-02-b-unify-task-execution-engine.md), [d-architecture-tab-migration.md](2026-04-02-d-architecture-tab-migration.md), [e-plans-tab-migration.md](2026-04-02-e-plans-tab-migration.md), [f-claude-chain-migration.md](2026-04-02-f-claude-chain-migration.md)

**Deliverables for downstream plans:**
- `PipelineNode` protocol
- `TaskSource` protocol + `AITask<Output>`
- `AnalyzerNode<Input, Output>`
- `PRStep`, `ReviewStep`
- `MarkdownTaskSource` (implements `TaskSource`, parses `- [ ]` / `## - [ ]`)
- `Pipeline` execution engine (stop, pause, start-at-index, progress)

---

## - [x] Phase 1: Inventory Execution Path Differences

**Skills used**: `swift-architecture`, `ai-dev-tools-review`
**Principles applied**: Read all three feature use-case sets before writing the table so every behavior is represented; flagged any behavior without a clear node home with ⚠️.

**Skills to read:** `swift-architecture`, `ai-dev-tools-review`

Perform a line-by-line comparison of `RunChainTaskUseCase.swift` and `ExecutePlanUseCase.swift`. The goal is to map every behavior to a future pipeline node type so that the Phase 2 interface design covers everything.

Files compared (actual paths in repo):
- `AIDevToolsKit/Sources/Features/ClaudeChainFeature/usecases/RunChainTaskUseCase.swift`
- `AIDevToolsKit/Sources/Features/MarkdownPlannerFeature/usecases/ExecutePlanUseCase.swift`

Also audited:
- `AIDevToolsKit/Sources/Features/ArchitecturePlannerFeature/usecases/` — all 12 use cases

### Inventory Table

| Behavior | Current location | Future pipeline node | Notes/risks |
|----------|-----------------|---------------------|-------------|
| Load project config (assignees, reviewers, max PRs) | `RunChainTaskUseCase` phase 1 | `Pipeline` config struct / `ProjectConfiguration` passed in | Config loaded once before pipeline starts; not a node itself |
| Fetch + checkout base branch | `RunChainTaskUseCase` phase 1 | Implicit pipeline setup step or `Pipeline` pre-run hook | Must run before `MarkdownTaskSource` reads the spec file |
| Load spec / find plan file | `RunChainTaskUseCase` (spec), `ExecutePlanUseCase` (plan path) | `MarkdownTaskSource` init | Both use `MarkdownPipelineSource`; unified in `MarkdownTaskSource` |
| Task discovery — `.task` format, skip completed + remote-branch-exists | `RunChainTaskUseCase` | `MarkdownTaskSource.nextTask()` | Branch-existence check is Chain-specific; needs a hook or subclass |
| Task index override (start at specific task) | `RunChainTaskUseCase` `options.taskIndex` | `Pipeline.startAtIndex` | Maps cleanly to the planned `start-at-index` API |
| Phase discovery — `.phase` format | `ExecutePlanUseCase` | `MarkdownTaskSource` (`.phase` format) | Already unified via `MarkdownPipelineSource(format:)` |
| Feature branch creation | `RunChainTaskUseCase` phase 1b | `PRStep` setup / pre-AI node | Chain-specific; not in Plans or Architecture tabs |
| Pre-action script | `RunChainTaskUseCase` phase 2 | `ScriptNode` (new, not in current plan) ⚠️ | No node defined for pre/post scripts in plan deliverables |
| Post-action script | `RunChainTaskUseCase` phase 4 | `ScriptNode` (new, not in current plan) ⚠️ | Same as pre-script; could be generalized as `ShellStep` |
| AI task execution (streaming) | `RunChainTaskUseCase` phase 3, `ExecutePlanUseCase.executePhase` | `AITask` node | Both use `client.run`; Chain uses free-form, Plans uses structured |
| Structured AI execution | `ExecutePlanUseCase` (`PhaseResult`), all ArchPlanner use cases | `AnalyzerNode<Input, Output>` | Schema-driven; Architecture tab uses this exclusively |
| Cost extraction after AI run | `RunChainTaskUseCase` | `PRStep` (post-AI cost capture) | `ChainPRHelpers.extractCost()` — Chain-specific metric |
| Commit uncommitted AI changes | `RunChainTaskUseCase` phase 5 | `PRStep` or a `CommitNode` ⚠️ | Not clearly a `PRStep` concern; may need its own node |
| Mark task/phase complete in markdown | `RunChainTaskUseCase`, `ExecutePlanUseCase` | `MarkdownTaskSource.markComplete(_:)` | Already unified via `MarkdownPipelineSource.markStepCompleted` |
| Staging-only early exit | `RunChainTaskUseCase` `options.stagingOnly` | `Pipeline` config `stagingOnly: Bool` | Already planned in `Pipeline` configuration struct |
| Review pass (optional AI re-review) | `RunChainTaskUseCase` phase 5b | `ReviewStep` | Structured output (`ReviewOutput`); conditional on `review.md` existing |
| Append review note to spec | `RunChainTaskUseCase.appendReviewNote` | `ReviewStep` post-action | Inline file mutation; belongs inside `ReviewStep` |
| Branch push | `RunChainTaskUseCase` phase 5 | `PRStep` | Direct `git push --force` |
| Repo slug detection | `RunChainTaskUseCase` | `PRStep` | `ChainPRHelpers.detectRepo` — Chain-specific |
| Capacity check (max open PRs) | `RunChainTaskUseCase` | `PRStep` | Throws `capacityExceeded`; guard runs before `gh pr create` |
| PR creation (draft, label, assignees, reviewers) | `RunChainTaskUseCase` | `PRStep` | Already-exists recovery also needed |
| PR number retrieval | `RunChainTaskUseCase` | `PRStep` | `gh pr view --json number` |
| Summary generation (AI PR description) | `RunChainTaskUseCase` phase 6 | `PRStep` or a `SummaryNode` ⚠️ | Non-fatal; could be a second `AITask` chained after `PRStep` |
| PR comment posting (cost + summary report) | `RunChainTaskUseCase` phase 7 | `PRStep` | `MarkdownReportFormatter` + `gh pr comment` |
| Time-limit enforcement | `ExecutePlanUseCase` | `Pipeline` config `maxMinutes: Int?` | Already planned in `Pipeline` configuration struct |
| Uncommitted-changes detection (warning) | `ExecutePlanUseCase` | `Pipeline` pre-run check / progress event | Not a node; emitted as `.uncommittedChanges` progress event |
| `executeMode: .all \| .next` | `ExecutePlanUseCase` | `Pipeline` config `executionMode` | Already planned |
| Credential resolution (`GH_TOKEN`) | `ExecutePlanUseCase.executePhase` | `Pipeline` config / env injection | Passed as `AIClientOptions.environment`; should be in pipeline setup |
| Skills injection into prompt | `ExecutePlanUseCase.parseSkillsToRead` | `MarkdownTaskSource` or `AITask` prompt builder ⚠️ | Parsed from plan file annotations; unclear if `MarkdownTaskSource` or `AITask` owns this |
| Phase failure + log write | `ExecutePlanUseCase` | `Pipeline` error handling + `PhaseLogNode` ⚠️ | Log directory managed outside node; needs a logging hook |
| Architecture diagram stop flag | `ExecutePlanUseCase` | `Pipeline` mid-run inspection hook ⚠️ | Checks for a `-architecture.json` sidecar file; no clear node home |
| Between-phases callback | `ExecutePlanUseCase` `betweenPhases` closure | `Pipeline` inter-node hook | Already covered by `Pipeline` execution loop design |
| 2-second delay between phases | `ExecutePlanUseCase` | `Pipeline` execution loop (rate-limit policy) ⚠️ | Hardcoded sleep; should be configurable or removed |
| Move plan to `completed/` | `ExecutePlanUseCase.moveToCompleted` | `MarkdownTaskSource` post-completion action ⚠️ | Or a `Pipeline.onAllCompleted` callback |
| Plan log writing (per-phase stdout) | `ExecutePlanUseCase.writePhaseLog` | `Pipeline` logging hook / `PhaseLogNode` ⚠️ | Decoupled from execution; best as a pipeline-level observer |
| Requirements extraction (AI) | `FormRequirementsUseCase` (ArchPlanner) | `AnalyzerNode<FeatureRequest, [Requirement]>` | Structured output only; SwiftData persistence is caller concern |
| Architecture info compilation (AI) | `CompileArchitectureInfoUseCase` (ArchPlanner) | `AnalyzerNode<JobContext, ArchInfoResult>` | Reads `ARCHITECTURE.md` from repo path |
| Layer planning (AI) | `PlanAcrossLayersUseCase` (ArchPlanner) | `AnalyzerNode<ArchInfoResult, [Component]>` | References prior step summary via SwiftData |
| Conformance scoring (AI) | `ScoreConformanceUseCase` (ArchPlanner) | `AnalyzerNode<[Component], [GuidelineMapping]>` | Structured output; mid-pipeline write to SwiftData |
| Implementation decision recording (AI) | `ExecuteImplementationUseCase` (ArchPlanner) | `AnalyzerNode<PhaseComponents, PhaseResponse>` | Phase-grouped loop; each group is one AI call |
| Report generation (non-AI) | `GenerateReportUseCase` (ArchPlanner) | Non-AI terminal node ⚠️ | No `AIClient` dependency; does not fit `AnalyzerNode` pattern |
| Followups compilation (AI) | `CompileFollowupsUseCase` (ArchPlanner) | `AnalyzerNode<JobContext, [Followup]>` | Post-execution analysis step |
| SwiftData-backed inter-step state | All ArchPlanner use cases | ⚠️ No node equivalent — Architecture tab owns this | ArchPlanner passes context via `PlanningJob` in SwiftData, not through node I/O; pipeline cannot own this |

### Flagged Items Without Clear Node Home

- **`ScriptNode`** — pre/post action scripts in Chain not in any planned deliverable. Recommend adding to Phase 2 design or scoping out.
- **`CommitNode`** — committing AI-generated changes is a distinct responsibility from `PRStep`. Needs explicit placement.
- **`SummaryNode`** — AI-generated PR summary could be its own node or folded into `PRStep`; decide in Phase 2.
- **Skills injection** — `parseSkillsToRead` reads plan file annotations; unclear whether `MarkdownTaskSource` or the `AITask` prompt-builder owns this.
- **Phase log writing** — best as a pipeline-level observer pattern (similar to `onProgress`), not a node.
- **Architecture diagram stop** — mid-pipeline file-existence check; best as a `Pipeline` inspection hook or `.phase` node side effect.
- **2-second inter-phase delay** — hardcoded; should be removed or made a configurable `Pipeline` policy.
- **Move-to-completed** — could be a `MarkdownTaskSource` callback or a `Pipeline.onAllCompleted` hook.
- **SwiftData-backed state (ArchPlanner)** — the Architecture tab's inter-step context lives in `PlanningJob` / SwiftData, not in node return values; the unified pipeline cannot own this and must treat `AnalyzerNode` outputs as opaque, with the caller persisting results.

## - [x] Phase 2: Design the Pipeline Framework

**Skills used**: `swift-architecture`, `configuration-architecture`
**Principles applied**: `PipelineSDK` confirmed as the right SDK-layer target; `Pipeline` is not generic over Output (type erasure via `PipelineContext`); pre/post scripts stay in `ClaudeChainService`, not a pipeline node; `ReviewStep` pauses via `CheckedContinuation` held by a `Pipeline` actor; `PipelineConfiguration` receives a resolved `AIClient`, not a credential service.

---

### Layer Placement

`PipelineSDK` is the correct target. It is already an SDK-layer target with no dependencies and lives at `AIDevToolsKit/Sources/SDKs/PipelineSDK`. Phase 3 will add dependencies on `AIOutputSDK` (for `AIClient`) and the git SDK (for `GitClient`) when the execution nodes are implemented.

`MarkdownParser` stays embedded in `PipelineSDK` — currently inline in `MarkdownPipelineSource`. No separate target needed. `MarkdownTaskSource` is the only type in the SDK that touches markdown.

---

### Naming: Existing vs. New Types

The existing `PipelineSDK` types are **data models** (describe pipeline shape for display/persistence). The new types are **execution nodes** (actually run async work). They coexist in Phase 3 until migration is complete.

Rename in Phase 3 to free up names for execution types:

| Existing name | Rename to | Reason |
|---|---|---|
| `Pipeline` (data model struct) | `PipelineState` | Free up `Pipeline` for the execution engine |
| `CreatePRStep` (data model) | `PRStepData` | Free up `PRStep` for the execution node |
| `ReviewStep` (data model) | `ReviewStepData` | Free up `ReviewStep` for the execution node |

---

### `PipelineNode` Protocol

Every node exposes an async `run` that receives an immutable context and returns an updated context. Cancellation is cooperative via `Task.checkCancellation()` inside node implementations — the `Pipeline` actor holds the parent task and calls `.cancel()`. Progress is reported via a callback rather than a stream so each node controls granularity.

```swift
public protocol PipelineNode: Sendable {
    var id: String { get }
    var displayName: String { get }

    func run(
        context: PipelineContext,
        onProgress: @Sendable (PipelineNodeProgress) -> Void
    ) async throws -> PipelineContext
}
```

---

### `PipelineContext`

A typed, immutable-by-default dictionary passed through the pipeline. Nodes read prior results and return an augmented copy with their own results written in. Type safety via `PipelineContextKey<Value>` — similar to SwiftUI `EnvironmentValues`.

```swift
public struct PipelineContext: Sendable {
    // nodes write and read via subscript:
    public subscript<Value: Sendable>(_ key: PipelineContextKey<Value>) -> Value? { get set }
}

public struct PipelineContextKey<Value: Sendable>: Sendable {
    public let name: String
    public init(_ name: String)
}
```

Well-known keys are defined as static constants on the node type that writes them:

| Key | Writer | Value type |
|---|---|---|
| `AITask.outputKey` | `AITask<Output>` | `Output` |
| `AITask.metricsKey` | `AITask<Output>` | `AIMetrics` (cost, duration, turns) |
| `PRStep.prURLKey` | `PRStep` | `String` |
| `PRStep.prNumberKey` | `PRStep` | `String` |
| `PipelineContext.injectedTaskSourceKey` | `AnalyzerNode` | `any TaskSource` |

---

### `TaskSource` Protocol and `PendingTask`

`TaskSource` yields `PendingTask` values and accepts completion notifications. No markdown knowledge — that belongs in `MarkdownTaskSource`.

```swift
public protocol TaskSource: Sendable {
    func nextTask() async throws -> PendingTask?
    func markComplete(_ task: PendingTask) async throws
}

public struct PendingTask: Sendable, Identifiable {
    public let id: String
    public let instructions: String
    public let skills: [String]   // skill names parsed from markdown annotations
}
```

`skills: [String]` carries names from `**Skills to read:**` annotations in the markdown source. Loading skill file content is the responsibility of `AITask` or the service layer — `PipelineSDK` does not read files for skills.

---

### `AITask<Output>` Generics

`AITask<Output>` is a generic execution node. `Output` is `String` for free-text AI runs; a `Decodable` type for structured output (uses `AIClient.runStructured`).

**The `Pipeline` is NOT generic over `Output`**. Each `AITask<Output>` writes its result to `PipelineContext` under its static `outputKey`. The service assembler that constructs the pipeline recovers the typed result from the final context.

```swift
public struct AITask<Output: Decodable & Sendable>: PipelineNode {
    public static var outputKey: PipelineContextKey<Output> { .init("AITask.output.\(Output.self)") }
    public static var metricsKey: PipelineContextKey<AIMetrics> { .init("AITask.metrics") }

    public let id: String
    public let displayName: String
    public let instructions: String
    public let client: any AIClient
    public let jsonSchema: String?   // nil → text output; non-nil → structured output

    // run() calls client.run or client.runStructured, writes to context, returns updated context
}
```

---

### `AnalyzerNode<Input, Output>`

Reads its input from a typed context key set by a prior node. Produces a typed structured output. If the output should beget new tasks (e.g. plan generation), writes a `TaskSource` to `PipelineContext.injectedTaskSourceKey`. The `Pipeline` checks for this key after each node and, if found, exhausts the task source before advancing to the next scheduled node.

```swift
public struct AnalyzerNode<Input: Sendable, Output: Decodable & Sendable>: PipelineNode {
    public static var outputKey: PipelineContextKey<Output> { .init("AnalyzerNode.output.\(Output.self)") }

    public let id: String
    public let displayName: String
    public let inputKey: PipelineContextKey<Input>
    public let buildPrompt: @Sendable (Input) -> String
    public let jsonSchema: String
    public let client: any AIClient

    // run() reads inputKey from context, calls client.runStructured,
    // writes Output to outputKey, optionally writes TaskSource to injectedTaskSourceKey
}
```

Mid-pipeline task injection mechanism: `AnalyzerNode.run()` can write a `TaskSource` to `context[PipelineContext.injectedTaskSourceKey]` if the output warrants it (e.g. a generated markdown plan). After the node returns, `Pipeline` detects the key, drains pending tasks via `AITask` execution, then continues with remaining scheduled nodes (e.g. an optional `PRStep`).

---

### `PRStep`

Handles branch push, PR creation, capacity check, and cost comment. Reads the AI cost metrics from `AITask.metricsKey`. Reads the active branch name from git (does not require it as a constructor parameter). Writes PR URL and number to context for downstream use.

```swift
public struct PRStep: PipelineNode {
    public static var prURLKey: PipelineContextKey<String> { .init("PRStep.prURL") }
    public static var prNumberKey: PipelineContextKey<String> { .init("PRStep.prNumber") }

    public let id: String
    public let displayName: String
    public let baseBranch: String
    public let configuration: ProjectConfiguration   // assignees, reviewers, labels, maxOpenPRs
    public let gitClient: GitClient

    // run() reads AITask.metricsKey from context for cost comment,
    // calls gitClient for push + branch name,
    // checks capacity (throws PipelineError.capacityExceeded if maxOpenPRs reached),
    // creates draft PR via gh CLI,
    // writes prURLKey and prNumberKey to context
}
```

---

### `ReviewStep`

Pauses the pipeline and waits for explicit user approval. Uses a `CheckedContinuation` held by the `Pipeline` actor. The Mac app model receives a `.pausedForReview` event, shows the approval UI, then calls `pipeline.approve()` or `pipeline.cancel()`.

```swift
public struct ReviewStep: PipelineNode {
    public let id: String
    public let displayName: String

    // run() calls onProgress(.pausedForReview), then suspends via CheckedContinuation.
    // Pipeline actor resumes the continuation when approve() or cancel() is called.
    // If cancel(): throws PipelineError.cancelled
}
```

The `Pipeline` actor stores the continuation and exposes:

```swift
public func approve() async  // resumes ReviewStep continuation with true
public func cancel() async   // resumes ReviewStep continuation with false (throws)
```

---

### `Pipeline` Execution Engine

```swift
public actor Pipeline {
    public init(
        nodes: [any PipelineNode],
        configuration: PipelineConfiguration,
        initialContext: PipelineContext = PipelineContext()
    )

    public func run(
        onProgress: @Sendable (PipelineEvent) -> Void
    ) async throws -> PipelineContext

    public func run(
        startingAt index: Int,
        onProgress: @Sendable (PipelineEvent) -> Void
    ) async throws -> PipelineContext

    public func stop() async
    public func approve() async   // resumes a paused ReviewStep
    public func cancel() async    // cancels a paused ReviewStep
}
```

Execution loop behavior:
1. Iterate nodes in order from `startIndex` (default 0).
2. After each node returns an updated context, check `context[PipelineContext.injectedTaskSourceKey]`. If set, consume all pending tasks from the source (respecting `executionMode`), then clear the key and continue.
3. If `maxMinutes` is set, check elapsed time before each node. If exceeded, stop gracefully.
4. If `executionMode == .nextOnly` and a `TaskSource` is active, run exactly one task then stop.
5. Emit `PipelineEvent` progress for node start, node completion, and pause states.

---

### `PipelineConfiguration`

`provider` is a resolved `any AIClient` — the Apps layer resolves credentials and constructs the client before passing it in. Features and SDKs never instantiate credential services.

```swift
public struct PipelineConfiguration: Sendable {
    public let executionMode: ExecutionMode
    public let maxMinutes: Int?
    public let stagingOnly: Bool
    public let provider: any AIClient

    public enum ExecutionMode: Sendable {
        case nextOnly  // run one task from TaskSource, then stop
        case all       // run all available tasks
    }
}
```

---

### `MarkdownTaskSource`

Wraps `MarkdownPipelineSource` for file I/O. `MarkdownParser` (currently inline in `MarkdownPipelineSource`) is the only markdown-aware type in `PipelineSDK`. No other node or type in the SDK knows about markdown.

Supports an optional `taskIndex: Int?` for ClaudeChain's start-at-specific-task behavior: when set, `nextTask()` returns only the task at that index and returns `nil` thereafter.

```swift
public struct MarkdownTaskSource: TaskSource {
    public let fileURL: URL
    public let format: MarkdownPipelineFormat
    public let taskIndex: Int?   // nil = sequential; non-nil = single specific task

    public init(fileURL: URL, format: MarkdownPipelineFormat, taskIndex: Int? = nil)
    public func nextTask() async throws -> PendingTask?
    public func markComplete(_ task: PendingTask) async throws
}
```

---

### Pre/Post Scripts

**Not a pipeline node.** Pre/post action scripts are ClaudeChain-specific. They stay in `ClaudeChainService` as service-level setup/teardown before and after the pipeline runs. Adding a `ScriptNode` to `PipelineSDK` for a single feature's use case is not warranted.

## - [ ] Phase 3: Implement PipelineSDK

**Skills to read:** `swift-architecture`

Implement everything designed in Phase 2. Do NOT wire into any existing feature.

Tasks:
- Create `PipelineSDK` target (or extend existing `PipelineSDK` if already present — audit first)
- Implement `PipelineNode` protocol
- Implement `TaskSource` protocol and `AITask<Output>`
- Implement `MarkdownTaskSource` — wraps `MarkdownParser`, handles `.task` (`- [ ]`) and `.phase` (`## - [ ]`) formats
- Implement `Pipeline` execution loop — drives nodes in sequence, handles stop/pause/start-at-index, emits progress events
- Implement `AITask` node execution — delegates to `AIClient` via `ProviderRegistry`
- Implement `AnalyzerNode` — structured AI output, mid-pipeline task injection mechanism
- Implement `PRStep` — PR creation, branch push, cost comment, capacity check (extracted from `RunChainTaskUseCase`)
- Implement `ReviewStep` — pause + async resume

Unit tests (cover before marking this phase complete):
- `MarkdownTaskSource`: next-task selection, all-tasks iteration, checkbox round-trip (marks correct line in file)
- `.task` and `.phase` format parsing
- `Pipeline` next-only vs. all-tasks execution modes
- `Pipeline` stop and pause/resume
- `Pipeline` start-at-index (skips earlier nodes)
- `AnalyzerNode` mid-pipeline task injection
- `PRStep` capacity check enforcement
