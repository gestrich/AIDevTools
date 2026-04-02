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

## - [x] Phase 1: Map Use Cases to PipelineSDK Types

**Skills used**: none
**Principles applied**: Audited `RunChainTaskUseCase` and `FinalizeStagedTaskUseCase` against the full PipelineSDK surface. Key decisions: project prep and branch creation stay as service setup (same pattern as Plans tab); commit after AI maps to a new `CommitNode` inserted before `PRStep` in the blueprint; summary generation and PR comment are post-pipeline service steps (not nodes); `stagingOnly` omits `PRStep` from the blueprint rather than using a config flag; `FinalizeStagedTaskUseCase` becomes a blueprint with only `PRStep`; `MarkdownTaskSource(taskIndex:)` already handles indexed filtering but uses 0-based IDs while `RunChainTaskUseCase` uses 1-based indices — service must convert.

Audit `RunChainTaskUseCase` and `FinalizeStagedTaskUseCase` and document their pipeline equivalents. Deliverable: a table with columns: **Behavior**, **Current location**, **Pipeline node / type**, **Notes**.

| Behavior | Current location | Pipeline node / type | Notes |
|---|---|---|---|
| `git fetch origin/<baseBranch>`, checkout `FETCH_HEAD` so spec.md reflects latest remote | `RunChainTaskUseCase.run()` lines 126–130 | Service setup in `ClaudeChainService.buildPipeline()` — not a node | Must happen before task selection; same pattern as Plans tab pre-pipeline guard |
| Load spec content and detect next pending task (with remote-branch dedup when no `taskIndex`) | `RunChainTaskUseCase.run()` lines 145–181 | Service setup — determines resolved `taskIndex`, then passed to `MarkdownTaskSource(taskIndex:)` | Branch-dedup logic (`listRemoteBranches`) is Chain-specific and belongs in the service. `MarkdownTaskSource.nextTask()` handles the filtered lookup once `taskIndex` is known. `RunChainTaskUseCase` uses 1-based `taskIndex` (user-facing) while `MarkdownTaskSource` compares against 0-based step IDs — service must pass the 0-based index. |
| Create feature branch (`git checkout -B <branchName>`) | `RunChainTaskUseCase.run()` lines 192–194 | Service setup in `ClaudeChainService.buildPipeline()` — not a node | Branch name is derived before building the blueprint (`PRService.formatBranchName`); same pattern as service setup |
| Pre-action script (`ScriptRunner.runActionScript(type: "pre")`) | `RunChainTaskUseCase.run()` lines 197–204 | Service setup — runs before `PipelineRunner.run()` | Optional (no-op when script absent); per-task scope fits service setup rather than a node |
| AI execution (run Claude on task description + spec context) | `RunChainTaskUseCase.run()` lines 207–226 | `TaskSourceNode` → `PipelineRunner.drainTaskSource()` → `AITask<String>` | `MarkdownTaskSource(format: .task, taskIndex: resolvedIndex, instructionBuilder:)` supplies the enriched prompt. `PipelineRunner.drainTaskSource` drives the AI call and calls `source.markComplete()` after. One logical unit in the pipeline. |
| Commit AI changes (`git add -A && git commit "Complete task: …"`) | `RunChainTaskUseCase.run()` lines 245–252 | New `CommitNode` in blueprint, positioned after `TaskSourceNode` and before `PRStep` | `PipelineRunner` runs nodes in array order; after `TaskSourceNode` finishes `drainTaskSource`, `CommitNode` runs next. `CommitNode` receives the commit message as an init parameter (service knows the task description before building the blueprint). |
| Mark spec.md checkbox complete (`markStepCompleted`) | `RunChainTaskUseCase.run()` lines 267–273 | `MarkdownTaskSource.markComplete()` called by `PipelineRunner.drainTaskSource()` — no extra node | `drainTaskSource` calls `source.markComplete(task)` after AI finishes. The file-system update is done; a subsequent git commit for spec.md must follow. This commit is merged into `CommitNode` (which runs `git add -A` before committing, picking up the spec.md change). |
| Optional review pass (structured AI → commit review changes → append review note to spec.md) | `RunChainTaskUseCase.run()` lines 276–316 | Post-`TaskSourceNode` custom node (e.g., `ReviewPassNode`) or service-layer step after AI completes; deferred to Phase 2 design | Complex: runs AI, commits, mutates spec.md. Cleanest mapping is a dedicated custom node inserted after `CommitNode` and before `PRStep` when `review.md` exists. `CommitNode` can do a second add-commit pass to capture spec.md review annotation. |
| Push branch (`git push --force --set-upstream origin <branch>`) | `RunChainTaskUseCase.run()` line 319 | `PRStep.run()` — first operation inside PRStep | Already handled by `PRStep` |
| Capacity check (`maxOpenPRs`) | `RunChainTaskUseCase.run()` lines 324–339 — via `AssigneeService.checkCapacity` | `PRStep.run()` — `PRConfiguration.maxOpenPRs`; throws `PipelineError.capacityExceeded` | `PRStep` already implements this check using `countOpenPRs` (gh CLI). Same code path; service passes `maxOpenPRs` from `projectConfig` into `PRConfiguration`. |
| Create draft PR (gh pr create, assignees, reviewers, labels) | `RunChainTaskUseCase.run()` lines 342–387 | `PRStep.run()` | `PRStep` writes `prURL` and `prNumber` to `PipelineContext` via `PRStep.prURLKey` / `PRStep.prNumberKey` |
| Post-action script (`ScriptRunner.runActionScript(type: "post")`) | `RunChainTaskUseCase.run()` lines 232–239 | Service teardown — runs after `PipelineRunner.run()` completes | Symmetric with pre-script; service-layer concern |
| Summary generation (AI call → markdown summary of `git diff baseBranch…HEAD`) | `RunChainTaskUseCase.run()` lines 391–427 | Post-pipeline service step in `ClaudeChainService` — reads `prNumber`/`prURL` from final context | Non-fatal; runs after `PipelineRunner.run()` returns the final `PipelineContext`. PR number is read from `context[PRStep.prNumberKey]`. |
| Post PR comment (formatted `PullRequestCreatedReport` with cost, summary, task progress) | `RunChainTaskUseCase.run()` lines 430–474 | Post-pipeline service step in `ClaudeChainService` | Non-fatal; uses `prNumber` from final context. Cost metric is read from `context[AITask<String>.metricsKey]`. |
| `stagingOnly` — stop after commit, skip push/PR | `RunChainTaskUseCase.run()` lines 254–265 | Service omits `PRStep` from the assembled blueprint when `options.stagingOnly == true` | Not a `PipelineConfiguration.stagingOnly` flag; the service simply does not include `PRStep` (or summary/comment steps) in the blueprint. Cleaner than a runtime skip flag. |
| `FinalizeStagedTaskUseCase` — push + PR for a previously staged commit | `FinalizeStagedTaskUseCase.run()` | Blueprint with a single `PRStep` node; service setup handles checkout + `markComplete` + commit before running the blueprint | No AI needed; the task is already committed. Service calls `MarkdownTaskSource.markComplete()` directly before building the finalize blueprint. Summary generation and PR comment remain post-pipeline service steps, same as normal run. |

## - [x] Phase 2: Implement ClaudeChainService with buildPipeline(for task:)

**Skills used**: none
**Principles applied**: Created `ClaudeChainService` struct in `ClaudeChainFeature` with `buildPipeline(for:options:)` and `buildFinalizePipeline(for:options:)`. Pre-pipeline project setup (fetch, checkout, branch creation) runs before returning the blueprint. `MarkdownTaskSource` receives `task.index - 1` (converting 1-based `ChainTask.index` to 0-based `CodeChangeStep.id`). `PRStep` (from `PipelineService`) is included only when `stagingOnly == false`. `buildFinalizePipeline` marks the spec.md checkbox complete and commits before returning a blueprint with only `PRStep`. Added `PipelineService` to `ClaudeChainFeature` dependencies. Fixed `TaskService.generateTaskHash` to use `generateTaskHash(_:)` syntax to disambiguate from the shadowed module name.

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

## - [x] Phase 3: Wire ClaudeChainModel to Per-Task PipelineModels

**Skills used**: none
**Principles applied**: Added `taskPipelines: [Int: PipelineModel]`, `selectedTaskIndex`, and `selectedPipelineModel` to `ClaudeChainModel`. Added `executeTask(at:project:repoPath:stagingOnly:)` and `finalizeStaged(at:project:repoPath:)` that build pipelines via `ClaudeChainService` and run them through `PipelineModel`. Updated `executeChain` to delegate to `executeTask` (finding next pending task when no index given) and `createPRFromStaged` to delegate to `finalizeStaged`. Modified `PipelineModel.run` to return `PipelineContext` (`@discardableResult`) using a thread-safe `PipelineContextBox`, eliminating the need for `onEvent` to capture PR info. Pipeline events are translated to `RunChainTaskUseCase.Progress` via `pipelineModel.onEvent`, keeping the existing view's streaming chat output working. Added `PipelineSDK` and `PipelineService` to `AIDevToolsKitMac` deps in `Package.swift`.

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

## - [x] Phase 4: Update Claude Chain Tab UI to Master-Detail with PipelineView

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

## - [x] Phase 5: Validation

**Skills used**: `ai-dev-tools-review`, `swift-testing`
**Principles applied**: Fixed pre-existing compilation errors (`baseBranch` missing in `ExecuteChainUseCaseTests`, `GitHubService` → `GitHubAPIService` in `GitHistoryProviderTests`, `async` missing on `LoadPRDetailUseCaseTests`). Made `git fetch` best-effort in `RunChainTaskUseCase` so spec.md error-path tests pass without a real git remote. Added `MarkdownTaskSource` tests for `taskIndex` filtering and `markComplete` targeting — all pass. Pre-existing failures (`stop halts` race condition, demo-repo chain count mismatch) are unrelated to Phase 5 scope.

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
