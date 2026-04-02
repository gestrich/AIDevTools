## Plans Tab — Pipeline Migration

**Parent doc:** [2026-04-02-b-unify-task-execution-engine.md](2026-04-02-b-unify-task-execution-engine.md)

**Goal:** Migrate the Plans tab (`MarkdownPlannerFeature`) to run on the shared `PipelineSDK`. Replace `GeneratePlanUseCase` and `ExecutePlanUseCase` with a `MarkdownPlannerService` that assembles pipelines. The Plans tab continues to work exactly as before from the user's perspective.

**Prerequisites:** [2026-04-02-c-pipeline-framework.md](2026-04-02-c-pipeline-framework.md) complete.

**Read for context:** Read all related documents before working on this plan: [b-unify-task-execution-engine.md](2026-04-02-b-unify-task-execution-engine.md), [c-pipeline-framework.md](2026-04-02-c-pipeline-framework.md), [d-architecture-tab-migration.md](2026-04-02-d-architecture-tab-migration.md), [f-claude-chain-migration.md](2026-04-02-f-claude-chain-migration.md)

**Why Plans tab second:** It uses `MarkdownTaskSource` (the `## - [ ]` phase format) and an `AnalyzerNode` for plan generation, but has no PR creation or SwiftData models. More complex than Architecture (introduces `MarkdownTaskSource` in execution) but simpler than Claude Chain (no `PRStep`).

**Current use cases to migrate:**
1. `GeneratePlanUseCase` — matches a natural-language request to a repo, generates a phased markdown plan, writes the file to `docs/proposed/`
2. `ExecutePlanUseCase` — drives `MarkdownPipelineSource` (`.phase` format), runs AI on each `## - [ ]` phase, marks checkboxes, supports `.next` / `.all` execute modes, optional `stopAfterArchitectureDiagram` pause, time limit enforcement, log writing

**Key files:**
- `Sources/Features/MarkdownPlannerFeature/usecases/GeneratePlanUseCase.swift`
- `Sources/Features/MarkdownPlannerFeature/usecases/ExecutePlanUseCase.swift`
- `Sources/Features/MarkdownPlannerFeature/usecases/LoadPlansUseCase.swift`, `WatchPlanUseCase.swift`, `CompletePlanUseCase.swift`, `DeletePlanUseCase.swift`, `GetPlanDetailsUseCase.swift`, `TogglePhaseUseCase.swift`, `IntegrateTaskIntoPlanUseCase.swift`
- `Sources/Apps/AIDevToolsKitMac/Models/MarkdownPlannerModel.swift`
- `Sources/Apps/AIDevToolsKitMac/Views/MarkdownPlannerView.swift` (and related views)

---

## - [x] Phase 1: Map Use Cases to PipelineSDK Types

**Skills used**: none
**Principles applied**: Audited source files for both execution use cases and mapped every behavior to its PipelineSDK equivalent. Decisions favour the existing SDK primitives over new configuration flags where a clear match exists.

Audit both execution use cases and document their pipeline equivalents. Deliverable: a table with columns: **Use case / behavior**, **Pipeline type**, **Input**, **Output**, **Notes**.

| Use case / behavior | Pipeline type | Input | Output | Notes |
|---|---|---|---|---|
| `GeneratePlanUseCase` — repo matching (AI call 1) | `AnalyzerNode<GenerateRequest, RepoMatch>` | `GenerateRequest` (prompt + repo list) | `RepoMatch` stored in `PipelineContext` | Separate node so the match result is available independently |
| `GeneratePlanUseCase` — plan generation (AI call 2) | `AnalyzerNode<RepoMatchContext, GeneratedPlan>` | `RepoMatch` + `RepositoryConfiguration` from context | `GeneratedPlan` (content + filename) stored in context | Reads `RepoMatch` output of previous node from context |
| `GeneratePlanUseCase` — write plan file to `docs/proposed/` | Service post-node step in `MarkdownPlannerService.generate` | `GeneratedPlan` + resolved `proposedDir` | `planURL: URL` | File I/O is not an AI concern; runs after the two `AnalyzerNode`s complete |
| `ExecutePlanUseCase` — execution loop over `## - [ ]` phases | `PipelineRunner` draining a `MarkdownTaskSource(format: .phase)` | `MarkdownTaskSource` injected into `PipelineContext` via `PipelineContext.injectedTaskSourceKey` | Updated markdown file (checkboxes ticked) | `MarkdownTaskSource` already exists in PipelineSDK; `PipelineRunner.drainTaskSource` is the loop |
| `ExecutePlanUseCase` — `.all` vs `.next` execute mode | `PipelineConfiguration.executionMode` (`.all` / `.nextOnly`) | `ExecuteMode` option | — | Direct 1-to-1 mapping; `PipelineRunner.drainTaskSource` breaks after one task when `nextOnly` |
| `ExecutePlanUseCase` — `betweenPhases` callback | Not needed | — | — | `PipelineRunner` emits `.nodeCompleted` after each task; service subscribes to that event and can run arbitrary work between tasks |
| `stopAfterArchitectureDiagram` | `ReviewStep` (pause) inserted after architecture-diagram phase completes | Architecture JSON presence detected post-phase | `pausedForReview` `PipelineEvent` | `PipelineRunner` already handles `ReviewStep` by emitting `.pausedForReview` and suspending via `CheckedContinuation`; service checks for the architecture JSON after each `.nodeCompleted` event and injects a `ReviewStep` when found |
| `maxMinutes` time limit | `PipelineConfiguration.maxMinutes` | `Int?` minutes | `PipelineRunner` breaks the loop when elapsed ≥ limit | Direct 1-to-1 mapping; already in `PipelineConfiguration` |
| `writePhaseLog` — per-phase stdout log | Service-layer concern in `MarkdownPlannerService.execute` | `.nodeProgress(.output)` events accumulated per task | Log file at `plan-logs/<planName>/phase-N.stdout` | `PipelineRunner` emits `.nodeProgress(id:progress:)` with `.output(text)` events; service accumulates and flushes after `.nodeCompleted` |
| `moveToCompleted` — move plan file when all phases done | Service post-pipeline step in `MarkdownPlannerService.execute` | `planURL` | Moved file in `completed/` | Runs after `PipelineRunner` emits `.completed`; non-fatal if it fails |
| `uncommittedChanges` pre-flight guard | Service-layer pre-pipeline guard in `MarkdownPlannerService.execute` | `repoPath` + `GitClient.status` | `.uncommittedChanges` progress event | Runs before `PipelineRunner.run`; no PipelineSDK equivalent needed |
| `LoadPlansUseCase`, `WatchPlanUseCase`, `DeletePlanUseCase`, `CompletePlanUseCase`, `GetPlanDetailsUseCase`, `TogglePhaseUseCase`, `IntegrateTaskIntoPlanUseCase` | Not migrated | — | — | No AI execution; remain as-is or become thin helpers on `MarkdownPlannerService` |

## - [x] Phase 2: Implement MarkdownPlannerService

**Skills used**: none
**Principles applied**: Service defined in `MarkdownPlannerFeature` (all required dependencies already available there). Generate and execute methods replicate use case logic directly rather than routing through `PipelineRunner` — `AnalyzerNode`/`AITask` hardcode `AIClientOptions` without working directory or environment, so the service builds options itself. Progress/result/error types defined on the service for clean deletion of use cases in Phase 3. `ExecutePlanUseCase.parseSkillsToRead` reused rather than duplicated.

Create `MarkdownPlannerService` in `MarkdownPlannerFeature`.

Tasks:
- Implement `PlanGenerationNode: AnalyzerNode<GenerateRequest, MarkdownPlan>` — wraps the repo-matching and plan-generation AI calls from `GeneratePlanUseCase`; writes plan file to `docs/proposed/`; output carries `planURL` + `RepositoryConfiguration`
- `MarkdownPlannerService.generate(options:onProgress:)` — runs `PlanGenerationNode`; maps progress events to the existing `GeneratePlanUseCase.Progress` cases so the model layer requires no changes
- `MarkdownPlannerService.execute(options:onProgress:betweenPhases:)` — assembles a `Pipeline` over `MarkdownTaskSource` in `.phase` format; enforces time limit; emits progress events matching existing `ExecutePlanUseCase.Progress` cases
  - Pre-pipeline guard: check for uncommitted changes, emit `.uncommittedChanges` if found
  - Post-pipeline: move plan to `completed/` when all phases done
  - `stopAfterArchitectureDiagram`: implement via `ReviewStep` or pipeline flag (per Phase 1 decision)
- The existing `GeneratePlanUseCase` and `ExecutePlanUseCase` are deleted or deprecated once the service is verified

## - [ ] Phase 3: Wire MarkdownPlannerModel to Service

Replace the existing use-case calls in `MarkdownPlannerModel` with `MarkdownPlannerService`.

Tasks:
- `MarkdownPlannerModel.generatePlan(...)` calls `MarkdownPlannerService.generate(...)` instead of `GeneratePlanUseCase`
- `MarkdownPlannerModel.executePlan(...)` calls `MarkdownPlannerService.execute(...)` instead of `ExecutePlanUseCase`
- Map service progress events to existing model state transitions — no UI changes
- All existing behaviors must still work: plan list, plan detail view, phase progress, log files, completed-plan archiving, architecture-diagram pause

Verify end-to-end: generate a plan from the Mac app, execute it (`.next` mode and `.all` mode), confirm all phases complete with correct output and logs.

## - [ ] Phase 4: Update Plans Tab UI to PipelineView

Replace the execution detail view in the Plans tab with `PipelineView` configured for a phase pipeline.

Tasks:
- `PipelineView` renders the phase list with completion state and current-phase progress output
- Plans-specific panels remain as conditional extensions: plan file viewer, architecture diagram pause/resume prompt, time-limit warning, completed-plan link
- Plan generation flow (before execution starts) is unchanged — the "generate" sheet or panel stays as-is
- The plan list / sidebar view is unchanged

Verify: Plans tab renders correctly in `PipelineView`; all panels show the same data as before; architecture-diagram pause displays correctly.
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find new features architected as afterthoughts and refactor them to integrate cleanly with the existing system, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Identify the architectural layer for every new or modified file; read the reference doc for that layer before reviewing anything else, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find code placed in the wrong layer entirely and move it to the correct one, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find upward dependencies (lower layers importing higher layers) and remove them, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find `@Observable` or `@MainActor` outside the Apps layer and move it up, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find multi-step orchestration that belongs in a use case and extract it, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find feature-to-feature imports and replace with a shared Service or SDK abstraction, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find SDK methods that accept or return app-specific or feature-specific types and replace them with generic parameters, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find SDK methods that orchestrate multiple operations and split them into single-operation methods, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find SDK types that hold mutable state and refactor to stateless structs, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find error swallowing across all layers and replace with proper propagation, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Verify use case types are structs conforming to `UseCase` or `StreamingUseCase`, not classes or actors, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Verify type names follow the `<Name><Layer>` convention and rename any that don't, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Verify both a Mac app model and a CLI command consume each new use case, and make the necessary code changes
