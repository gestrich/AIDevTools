## Claude Chain Tab — Pipeline Migration

**Parent doc:** [2026-04-02-b-unify-task-execution-engine.md](2026-04-02-b-unify-task-execution-engine.md)

**Goal:** Migrate the Claude Chain tab (`ClaudeChainFeature`) to run on the shared `PipelineSDK`. Replace `RunChainTaskUseCase`, `ExecuteChainUseCase`, and `FinalizeStagedTaskUseCase` with a `ClaudeChainService` that builds a per-task `PipelineBlueprint`. Each chain task is its own independent pipeline — not a phase inside a shared pipeline. The UI becomes a master-detail: the task list on the left, the selected task's `PipelineView` on the right.

**Prerequisites:** [2026-04-02-c-pipeline-framework.md](2026-04-02-c-pipeline-framework.md) complete.

**Read for context:** Read all related documents before working on this plan: [b-unify-task-execution-engine.md](2026-04-02-b-unify-task-execution-engine.md), [c-pipeline-framework.md](2026-04-02-c-pipeline-framework.md), [d-architecture-tab-migration.md](2026-04-02-d-architecture-tab-migration.md), [e-plans-tab-migration.md](2026-04-02-e-plans-tab-migration.md), [g-implementation-model-plans-integration.md](2026-04-02-g-implementation-model-plans-integration.md)

**Why Claude Chain tab last:** It is the most complex migration — it has `PRStep` (push + PR creation + capacity check), summary generation, PR comment posting, staging-only mode, per-task index selection, and `FinalizeStagedTaskUseCase`. Doing this last means `PRStep` is already battle-tested from the framework plan.

**Key architectural difference from Plans tab:** In the Plans tab, all phases share one `PipelineModel` — they are sequential steps in a single pipeline run. In Claude Chain, each task is an entirely separate pipeline: its own git branch, its own AI context window, its own PR. The Plans tab maps phases → pipeline nodes. Claude Chain maps tasks → independent pipelines.

**Shared markdown infrastructure:** Both tabs use the same `MarkdownTaskSource` from `PipelineSDK`. The only difference is the format enum: Plans uses `.phase` (`## - [ ]` headers), Claude Chain uses `.task` (`- [ ]` items). `MarkdownParser` is shared and must not be duplicated.

**Current use cases to migrate:**
1. `ExecuteChainUseCase` — entry point; resolves project, calls `RunChainTaskUseCase`
2. `RunChainTaskUseCase` — the full execution path per task:
   - Prepare project: `git fetch`, checkout base branch, pull, create/checkout feature branch
   - Run AI (code changes via `AIClient`)
   - Commit changes
   - If not `stagingOnly`: push branch, create PR, enforce capacity check, generate summary, post PR comment, mark spec.md checkbox complete
3. `FinalizeStagedTaskUseCase` — for staged tasks: push + PR creation + summary + comment after manual review
4. `ListChainsUseCase` / `ListChainsFromGitHubUseCase` — chain discovery (not execution; NOT migrated)
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
- AI execution + commit — is this one `TaskNode` or two nodes? Confirm how `MarkdownTaskSource` feeds the task description for a single filtered task and how `taskIndex` filtering is applied.
- `PRStep` inputs: what does it need from the preceding AI node? (branch name, commit message, cost metrics) — confirm these flow via pipeline context.
- Summary generation + PR comment — are these part of `PRStep`, a separate `ReviewStep`, or a post-`PRStep` node?
- `stagingOnly` — does this become a pipeline configuration flag that skips `PRStep`, or does the service simply not include `PRStep` in the assembled pipeline?
- `FinalizeStagedTaskUseCase` — does this become a separate single-node pipeline (`PRStep` only) or reuse `PRStep` directly?
- Capacity check (`maxOpenPRs`) — already in `PRStep` per the framework plan; confirm the check uses the same `GitHubClient` path as today.

## - [ ] Phase 2: Implement ClaudeChainService with buildPipeline(for task:)

Create `ClaudeChainService` in `ClaudeChainFeature`.

Each call to `buildPipeline` produces a `PipelineBlueprint` for **one task** — a self-contained pipeline that goes from AI execution through PR creation. The caller creates a fresh `PipelineModel` and runs this blueprint independently.

Tasks:
- `ClaudeChainService.buildPipeline(for task: ChainTask, options: ChainRunOptions) -> PipelineBlueprint`:
  - Performs project preparation (fetch, checkout base branch, pull, create feature branch) as setup *before* returning the blueprint — not inside a node
  - Builds `instructionBuilder` closure for `MarkdownTaskSource` — enriches raw task description with repo context, branch, commit instructions
  - Filters `MarkdownTaskSource` to the specific `task.index` so it yields exactly one task
  - `environment`: inject `GH_TOKEN` from credentials (same pattern as Plans tab)
  - If `options.stagingOnly == false`: include `PRStep` node after `TaskSourceNode`
  - Returns `PipelineBlueprint(nodes: [taskSourceNode, prStep?], configuration: config, initialNodeManifest: manifest)`
- `ClaudeChainService.buildFinalizePipeline(for task: ChainTask, options: ChainRunOptions) -> PipelineBlueprint`:
  - Replaces `FinalizeStagedTaskUseCase`
  - Blueprint contains just a `PRStep` node (code already committed; only push + PR needed)
- Delete or deprecate `RunChainTaskUseCase`, `ExecuteChainUseCase`, and `FinalizeStagedTaskUseCase` once service is verified
- Post-pipeline: marking spec.md checkbox complete is handled by `MarkdownTaskSource.markComplete()` — no extra step needed

## - [ ] Phase 3: Wire ClaudeChainModel to Per-Task PipelineModels

Replace the existing use-case calls in `ClaudeChainModel` with `ClaudeChainService` + per-task `PipelineModel` instances.

**Core model change:** `ClaudeChainModel` holds a dictionary of `PipelineModel`s, one per task index. This is the fundamental difference from the Plans tab (which has one shared `PipelineModel`).

Tasks:
- Add `var taskPipelines: [Int: PipelineModel] = [:]` as a stored property on `ClaudeChainModel`
- Add `var selectedTaskIndex: Int?` — tracks which task is selected in the sidebar
- Add computed property `var selectedPipelineModel: PipelineModel? { taskPipelines[selectedTaskIndex ?? -1] }`
- `ClaudeChainModel.executeTask(at index: Int)`:
  - Creates a new `PipelineModel` for that index
  - Calls `service.buildPipeline(for: task, options: ...)` → `pipelineModel.run(blueprint:)`
  - Stores result in `taskPipelines[index]`
- `ClaudeChainModel.finalizeStaged(at index: Int)`:
  - Calls `service.buildFinalizePipeline(for: task, options: ...)` → `pipelineModel.run(blueprint:)`
  - Stores result in `taskPipelines[index]`
- All existing behaviors must still work: per-task play buttons (pass `taskIndex`), staging-only mode, finalize-staged flow, PR creation, PR comment, reset on dismiss
- `baseBranch` still sourced from `ChainProject.baseBranch`; service receives it via options

Verify end-to-end: run a full chain task from the Mac app (both normal and staging-only), finalize a staged task, confirm PR created and comment posted.

## - [ ] Phase 4: Update Claude Chain Tab UI to Master-Detail with PipelineView

Wire `ClaudeChainDetailView` to `PipelineView` in a master-detail layout. Selecting a task in the sidebar shows that task's `PipelineView`.

Tasks:
- `ClaudeChainDetailView` becomes a master-detail split:
  - **Left / master**: task list — each row shows task description, completion state, and a per-task play button; tapping a row sets `ClaudeChainModel.selectedTaskIndex`
  - **Right / detail**: `PipelineView` bound to `claudeChainModel.selectedPipelineModel`; shows "no task selected" placeholder when `selectedPipelineModel` is nil
- Inject the selected `PipelineModel` via `.environment(selectedPipelineModel)` on `PipelineView`
- `PipelineView` renders the pipeline phases with completion state and current-task streaming output — no Chain-specific code needed inside `PipelineView`
- Chain-specific panels remain in `ClaudeChainDetailView` as conditional extensions: staging-only toggle, finalize-staged button, PR link, PR comment preview
- `ChainProjectListView` (sidebar) and chain project selection are unchanged
- `@AppStorage("chainCreatePR")` toggle stays in the header bar
- Previously completed tasks: if `taskPipelines[index]` already exists (from a past run in this session), selecting that task shows its completed `PipelineView` — the run history is visible

Verify: Claude Chain tab renders correctly in master-detail layout; selecting different tasks shows the correct `PipelineView` for each; per-task play buttons work; staging-only and finalize-staged flows work; PR link appears on completion.

## - [ ] Phase 5: Validation

**Skills to read:** `ai-dev-tools-review`, `swift-testing`

**Note:** Before running CLI validation, check github.com/gestrich-claude for Claude Chain demo repo docs and setup instructions.

End-to-end validation uses the demo app chain as the target. Create a fresh chain in the Mac app pointing at the demo repo, then drive it entirely via CLI commands.

Automated:
- Run all unit tests in `ClaudeChainFeature` and `PipelineSDK`
- Verify `MarkdownTaskSource` correctly filters to a single `taskIndex` and marks only that task complete

Manual / CLI (using the demo chain):
- **First run:** Run `claude-chain run-task` — verify a git branch is created, AI executes the first task, a commit is made, and a PR is opened on the demo repo
- **Second run:** With `maxOpenPRs` set to 2, run `claude-chain run-task` again — verify a second branch is created and a second PR is opened (capacity allows it)
- **Capacity block:** With `maxOpenPRs` set to 1 and one open PR, run `claude-chain run-task` — verify the capacity check blocks the run and no new PR is created
- **Staging-only run:** Run with `--staging-only` — verify AI runs and commits but no PR is created
- **Finalize staged:** Run `claude-chain finalize-staged` — verify the staged commit is pushed and a PR is opened
- **Mac app:** Select each task in the sidebar and verify its `PipelineView` shows the correct run state and PR link

Success criteria:
- Running the CLI once against the demo chain produces exactly one PR
- Running a second time (with `maxOpenPRs: 2`) produces a second PR for the second task
- Running with one open PR and `maxOpenPRs: 1` is blocked by the capacity check
- Each task has its own independent `PipelineModel` and pipeline run
- Selecting a task in the Mac app sidebar shows its `PipelineView`
- No regression in any existing Claude Chain behavior
- `RunChainTaskUseCase`, `ExecuteChainUseCase`, and `FinalizeStagedTaskUseCase` are deleted or deprecated
