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

## - [ ] Phase 1: Inventory Execution Path Differences

**Skills to read:** `swift-architecture`, `ai-dev-tools-review`

Perform a line-by-line comparison of `RunChainTaskUseCase.swift` and `ExecutePlanUseCase.swift`. The goal is to map every behavior to a future pipeline node type so that the Phase 2 interface design covers everything.

Files to compare:
- `Sources/Features/ClaudeChainFeature/usecases/RunChainTaskUseCase.swift`
- `Sources/Features/MarkdownPlannerFeature/usecases/ExecutePlanUseCase.swift`

Also audit:
- `Sources/Features/ArchitecturePlannerFeature/usecases/` — all use cases, to understand the multi-step analysis pipeline they form

Produce a table with columns: **Behavior**, **Current location**, **Future pipeline node**, **Notes/risks**. Flag anything without a clear node home. This table drives Phase 2 design decisions.

## - [ ] Phase 2: Design the Pipeline Framework

**Skills to read:** `swift-architecture`, `configuration-architecture`

Design all interfaces. No code written yet — document decisions inline in this plan before Phase 3 begins. Bill reviews and approves before implementation starts.

Decisions to make:

**`PipelineNode` protocol**
- What does every node expose? (async `run(context:)`, progress events, cancellation)
- How does a node receive inputs from prior nodes? (typed context object passed through, or explicit typed chaining?)

**`TaskSource` protocol**
- `func nextTask() -> AITask?`
- `func markComplete(_ task: AITask)`
- What does `AITask` carry? (`id`, `instructions: String`, output type token)

**`AITask<Output>` generics**
- Does the `Pipeline` need to be typed over `Output`, or does each node erase to `Any` internally?
- How does a consumer (e.g. `ClaudeChainService`) recover the typed result?

**`AnalyzerNode<Input, Output>`**
- Input: prior context or explicit typed value
- Output: typed artifact (e.g. `MarkdownPlan`, `ArchitectureDiagram`, `ConformanceReport`)
- Mid-pipeline task injection: when `AnalyzerNode` produces a `MarkdownPlan`, how does it splice a new `MarkdownTaskSource` into the running pipeline?

**`PRStep`**
- Inputs: branch name, base branch, `ProjectConfiguration`
- How does it receive the result of the preceding `AITask`? (cost metrics, git diff)

**`ReviewStep`**
- How does the pipeline pause and surface the approval gate to the Mac app?
- What does resume look like? (continuation, callback, async signal?)

**`Pipeline` configuration struct**
- `executionMode: .nextOnly | .all`
- `maxMinutes: Int?`
- `stagingOnly: Bool`
- `provider: AIProvider`

**`MarkdownTaskSource`**
- Confirm it implements `TaskSource`
- Confirm `MarkdownParser` is the only markdown-aware type — `MarkdownTaskSource` uses it; no other node knows about markdown

**Layer placement**
- Confirm `PipelineSDK` is the right target name with `swift-architecture`
- `MarkdownParser` stays in `PipelineSDK` or moves to its own target?

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
