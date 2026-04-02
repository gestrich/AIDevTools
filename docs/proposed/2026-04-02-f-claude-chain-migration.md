## Claude Chain Tab — Pipeline Migration

**Parent doc:** [2026-04-02-b-unify-task-execution-engine.md](2026-04-02-b-unify-task-execution-engine.md)

**Goal:** Migrate the Claude Chain tab (`ClaudeChainFeature`) to run on the shared `PipelineSDK`. Replace `RunChainTaskUseCase` and `ExecuteChainUseCase` with a `ClaudeChainService` that assembles a pipeline of `TaskNode` + `PRStep` steps. The Claude Chain tab continues to work exactly as before from the user's perspective, including per-task play buttons, staging-only mode, and finalize-staged flow.

**Prerequisites:** [2026-04-02-c-pipeline-framework.md](2026-04-02-c-pipeline-framework.md) complete.

**Read for context:** Read all related documents before working on this plan: [b-unify-task-execution-engine.md](2026-04-02-b-unify-task-execution-engine.md), [c-pipeline-framework.md](2026-04-02-c-pipeline-framework.md), [d-architecture-tab-migration.md](2026-04-02-d-architecture-tab-migration.md), [e-plans-tab-migration.md](2026-04-02-e-plans-tab-migration.md), [g-pipeline-model-and-generic-ui.md](2026-04-02-g-pipeline-model-and-generic-ui.md)

**Prerequisites from g-doc (already complete):** `PipelineBlueprint`, `TaskSourceNode`, `MarkdownTaskSource.instructionBuilder`, `PipelineConfiguration.betweenTasks/workingDirectory/environment`, `AITask` workingDirectory/environment support, `PipelineModel`, and generic `PipelineView` are all implemented. This tab only needs to implement `buildPipeline()` on `ClaudeChainService`, wire `ClaudeChainModel` to `PipelineModel`, and update `ClaudeChainView`.

**Why Claude Chain tab last:** It is the most complex migration — it has `PRStep` (push + PR creation + capacity check), summary generation, PR comment posting, staging-only mode, per-task index selection, and `FinalizeStagedTaskUseCase`. Doing this last means `PRStep` is already battle-tested from the framework plan.

**Current use cases to migrate:**
1. `ExecuteChainUseCase` — entry point; resolves project, calls `RunChainTaskUseCase`
2. `RunChainTaskUseCase` — the full execution path:
   - Prepare project: `git fetch`, checkout base branch, pull, create/checkout feature branch
   - Run AI (code changes via `AIClient`)
   - Commit changes
   - If not `stagingOnly`: push branch, create PR, enforce capacity check, generate summary, post PR comment, mark spec.md checkbox complete
3. `FinalizeStagedTaskUseCase` — for staged tasks: push + PR creation + summary + comment after manual review
4. `ListChainsUseCase` / `ListChainsFromGitHubUseCase` — chain discovery (not execution; these are NOT migrated)
5. `GetChainDetailUseCase`, `DiscoverChainsFromGitHubUseCase`, `CreateChainProjectUseCase` — utility use cases (NOT migrated)

**Key files:**
- `Sources/Features/ClaudeChainFeature/usecases/RunChainTaskUseCase.swift`
- `Sources/Features/ClaudeChainFeature/usecases/ExecuteChainUseCase.swift`
- `Sources/Features/ClaudeChainFeature/usecases/FinalizeStagedTaskUseCase.swift`
- `Sources/Services/ClaudeChainService/ChainModels.swift`
- `Sources/Apps/AIDevToolsKitMac/Models/ClaudeChainModel.swift`
- `Sources/Apps/AIDevToolsKitMac/Views/ClaudeChainView.swift`

---

## - [ ] Phase 1: Map Use Cases to PipelineSDK Types

Audit `RunChainTaskUseCase` and `FinalizeStagedTaskUseCase` and document their pipeline equivalents. Deliverable: a table with columns: **Behavior**, **Current location**, **Pipeline node / type**, **Notes**.

Items to determine:
- Project preparation (fetch, checkout, pull, branch creation) — service setup before pipeline starts, or a dedicated `SetupNode`?
- AI execution + commit — is this one `TaskNode` (AI runs, then commits inside the node) or two nodes? Confirm how `MarkdownTaskSource` (`.task` format) feeds the task description and how `taskIndex` filtering is applied.
- `PRStep` inputs: what does it need from the preceding AI node? (branch name, commit message, cost metrics) — confirm these flow via pipeline context
- Summary generation + PR comment — are these part of `PRStep`, a separate `ReviewStep`, or a post-`PRStep` node?
- `stagingOnly` — does this become a `Pipeline` configuration flag that skips `PRStep`, or does the service simply not include `PRStep` in the assembled pipeline?
- `FinalizeStagedTaskUseCase` — does this become a separate `Pipeline` (push + PR + summary + comment) or reuse `PRStep` directly?
- Capacity check (`maxOpenPRs`) — already in `PRStep` per the framework plan; confirm the check uses the same `GitHubClient` path as today

## - [ ] Phase 2: Implement ClaudeChainService with buildPipeline()

Create `ClaudeChainService` in `ClaudeChainFeature`.

**Pattern established in g-doc:** The service builds a `PipelineBlueprint`; `PipelineModel` runs it. The service does not call `PipelineRunner` directly.

Tasks:
- `ClaudeChainService.buildPipeline(options:) -> PipelineBlueprint` — main entry point replacing `ExecuteChainUseCase` + `RunChainTaskUseCase`:
  - Performs project preparation (fetch, checkout, branch) as setup *before* returning the blueprint — not inside a node
  - Builds `instructionBuilder` closure for `MarkdownTaskSource` — enriches raw task description with repo context, branch, commit instructions (using `.task` format on `spec.md`; filters to `options.taskIndex` if set)
  - Pre-reads `spec.md` tasks → `initialNodeManifest` (one entry per task)
  - `betweenTasks`: not needed for Claude Chain (next-only, one task per run)
  - `environment`: inject `GH_TOKEN` from credentials (same pattern as Plans tab)
  - If `stagingOnly == false`: append `PRStep` node after `TaskSourceNode`
  - Returns `PipelineBlueprint(nodes: [taskSourceNode, prStep?], configuration: config, initialNodeManifest: manifest)`
- `ClaudeChainService.buildFinalizePipeline(options:) -> PipelineBlueprint` — replaces `FinalizeStagedTaskUseCase`; blueprint contains just a `PRStep` node
- The existing `RunChainTaskUseCase`, `ExecuteChainUseCase`, and `FinalizeStagedTaskUseCase` are deleted or deprecated once the service is verified
- Post-pipeline: marking spec.md checkbox complete after the task runs is handled by `MarkdownTaskSource.markComplete()` — no extra step needed

## - [ ] Phase 3: Wire ClaudeChainModel to PipelineModel

Replace the existing use-case calls in `ClaudeChainModel` with `ClaudeChainService` + `PipelineModel`.

**Pattern established in g-doc:** Tab model owns a `PipelineModel`. Calls `service.buildPipeline()` → `pipelineModel.run(blueprint:)`.

Tasks:
- Add `let pipelineModel = PipelineModel()` as a stored property on `ClaudeChainModel`
- `ClaudeChainModel.executeChain(...)` calls `service.buildPipeline(...)` → `pipelineModel.run(blueprint:)`
- `ClaudeChainModel.finalizeStaged(...)` calls `service.buildFinalizePipeline(...)` → `pipelineModel.run(blueprint:)`
- All existing behaviors must still work: per-task play buttons (pass `taskIndex` to service), staging-only mode, finalize-staged flow, PR creation, PR comment, reset on dismiss
- `baseBranch` still sourced from `ChainProject.baseBranch`; service receives it via options
- Wire `pipelineModel.onEvent` to feed `ChatMessagesView` (same pattern as Plans tab — `.nodeStarted` → status message, `.nodeProgress(.output)` → stream, `.nodeCompleted` → finalize)

Verify end-to-end: run a full chain task from the Mac app (both normal and staging-only), finalize a staged task, confirm PR created and comment posted.

## - [ ] Phase 4: Update Claude Chain Tab UI to PipelineView

`PipelineView` is already generic (from g-doc). Wire `ClaudeChainDetailView` to it.

Tasks:
- Inject `claudeChainModel.pipelineModel` via `.environment(pipelineModel)` on `PipelineView`
- `PipelineView` renders the task list with completion state and current-task streaming output — no Chain-specific code needed
- Chain-specific panels remain in `ClaudeChainDetailView` as conditional extensions: staging-only toggle, finalize-staged button, PR link, PR comment preview
- `ChainProjectListView` (sidebar) and chain selection are unchanged
- `@AppStorage("chainCreatePR")` toggle stays in the header bar
- Per-task play buttons: each task row in `ClaudeChainDetailView`'s sidebar passes `taskIndex` to `ClaudeChainModel.executeChain()` — `PipelineView` handles progress display only

Verify: Claude Chain tab renders correctly in `PipelineView`; per-task play buttons work; staging-only and finalize-staged flows work; PR link appears on completion.
