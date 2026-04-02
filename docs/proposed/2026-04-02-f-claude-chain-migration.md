## Claude Chain Tab — Pipeline Migration

**Parent doc:** [2026-04-02-b-unify-task-execution-engine.md](2026-04-02-b-unify-task-execution-engine.md)

**Goal:** Migrate the Claude Chain tab (`ClaudeChainFeature`) to run on the shared `PipelineSDK`. Replace `RunChainTaskUseCase` and `ExecuteChainUseCase` with a `ClaudeChainService` that assembles a pipeline of `TaskNode` + `PRStep` steps. The Claude Chain tab continues to work exactly as before from the user's perspective, including per-task play buttons, staging-only mode, and finalize-staged flow.

**Prerequisites:** [2026-04-02-c-pipeline-framework.md](2026-04-02-c-pipeline-framework.md) complete.

**Read for context:** Read all related documents before working on this plan: [b-unify-task-execution-engine.md](2026-04-02-b-unify-task-execution-engine.md), [c-pipeline-framework.md](2026-04-02-c-pipeline-framework.md), [d-architecture-tab-migration.md](2026-04-02-d-architecture-tab-migration.md), [e-plans-tab-migration.md](2026-04-02-e-plans-tab-migration.md)

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

## - [ ] Phase 2: Implement ClaudeChainService

Create `ClaudeChainService` in `ClaudeChainFeature`.

Tasks:
- `ClaudeChainService.execute(options:onProgress:)` — service entry point replacing `ExecuteChainUseCase` + `RunChainTaskUseCase`
  - Performs project preparation (fetch, checkout, branch) as setup before the pipeline
  - Assembles pipeline: `[MarkdownTaskSource → TaskNode → PRStep?]`
  - `MarkdownTaskSource` uses `.task` format on `spec.md`; `options.taskIndex` filters to the specific task
  - `TaskNode` runs AI, commits; emits progress events matching existing `RunChainTaskUseCase.Progress` cases
  - If `stagingOnly == false`: appends `PRStep` (push + PR creation + capacity check + summary + PR comment)
  - After pipeline: marks spec.md checkbox complete (if not stagingOnly)
  - Progress events mirror existing `RunChainTaskUseCase.Progress` cases so `ClaudeChainModel` requires minimal changes
- `ClaudeChainService.finalizeStaged(options:onProgress:)` — replaces `FinalizeStagedTaskUseCase`; reuses `PRStep` for push + PR + summary + comment
- Extract `PRStep` logic from `RunChainTaskUseCase` into the `PipelineSDK`-level `PRStep` type (per framework plan Phase 3); `ClaudeChainService` uses it directly
- The existing `RunChainTaskUseCase`, `ExecuteChainUseCase`, and `FinalizeStagedTaskUseCase` are deleted or deprecated once the service is verified

## - [ ] Phase 3: Wire ClaudeChainModel to Service

Replace the existing use-case calls in `ClaudeChainModel` with `ClaudeChainService`.

Tasks:
- `ClaudeChainModel.executeChain(...)` calls `ClaudeChainService.execute(...)` instead of `ExecuteChainUseCase`
- `ClaudeChainModel.finalizeStaged(...)` calls `ClaudeChainService.finalizeStaged(...)` instead of `FinalizeStagedTaskUseCase`
- Map service progress events to existing model state transitions — no UI changes
- All existing behaviors must still work: per-task play buttons, staging-only mode, finalize-staged flow, PR creation, PR comment, reset on dismiss
- `baseBranch` still sourced from `ChainProject.baseBranch` (non-optional); service receives it via options

Verify end-to-end: run a full chain task from the Mac app (both normal and staging-only), finalize a staged task, confirm PR created and comment posted.

## - [ ] Phase 4: Update Claude Chain Tab UI to PipelineView

Replace `ClaudeChainDetailView`'s execution section with `PipelineView` configured for a task pipeline.

Tasks:
- `PipelineView` renders the task list with completion state, per-task play buttons, and current-task AI output
- Chain-specific panels remain as conditional extensions: staging-only toggle, finalize-staged button, PR link, PR comment preview
- `ChainProjectListView` (sidebar) and chain selection are unchanged
- `@AppStorage("chainCreatePR")` toggle stays in the header bar

Verify: Claude Chain tab renders correctly in `PipelineView`; per-task play buttons work; staging-only and finalize-staged flows work; PR link appears on completion.

## - [ ] Phase 5: Unified PipelineView Polish

After all three tabs are on `PipelineView`, do a single pass to ensure visual and behavioral consistency across the Architecture, Plans, and Claude Chain tabs.

Tasks:
- Confirm node labels, progress indicators, and completion states look consistent across all three tabs in `PipelineView`
- Confirm cancellation / stop behavior is consistent (all tabs can stop a running pipeline)
- Confirm error display is consistent (all tabs show node-level error details in the same format)
- No functional changes — polish only
