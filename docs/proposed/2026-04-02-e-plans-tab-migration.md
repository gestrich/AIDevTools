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

## - [ ] Phase 1: Map Use Cases to PipelineSDK Types

Audit both execution use cases and document their pipeline equivalents. Deliverable: a table with columns: **Use case / behavior**, **Pipeline type**, **Input**, **Output**, **Notes**.

Items to determine:
- `GeneratePlanUseCase` — repo matching + plan generation is two AI calls in sequence. Does this become one `AnalyzerNode<GenerateRequest, MarkdownPlan>` or two chained nodes? The plan file URL and `RepositoryConfiguration` are the outputs consumed by the execution pipeline.
- `ExecutePlanUseCase`'s execution loop is already backed by `MarkdownPipelineSource` — how does this map to `Pipeline` + `MarkdownTaskSource` (`.phase` format)? What replaces the `betweenPhases` callback?
- `stopAfterArchitectureDiagram` — does this become a `ReviewStep` (pause for user inspection) or a `Pipeline` configuration flag?
- Time limit (`maxMinutes`) — is this a `Pipeline` configuration field or enforced in the service?
- Log writing (`writePhaseLog`) — service-layer concern or part of the node?
- `moveToCompleted` (file move on all-done) — service-layer post-pipeline step
- `uncommittedChanges` progress event — pre-pipeline guard in the service
- Use cases that are NOT execution (`LoadPlansUseCase`, `WatchPlanUseCase`, `DeletePlanUseCase`, etc.) — these are not migrated; they remain as-is or become thin service helpers

## - [ ] Phase 2: Implement MarkdownPlannerService

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
