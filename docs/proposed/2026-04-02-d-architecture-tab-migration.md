## Architecture Tab — Pipeline Migration

**Parent doc:** [2026-04-02-b-unify-task-execution-engine.md](2026-04-02-b-unify-task-execution-engine.md)

**Goal:** Migrate the Architecture tab (`ArchitecturePlannerFeature`) to run on the shared `PipelineSDK`. Replace the current ad-hoc use-case chain with an `ArchitecturePlannerService` that assembles a pipeline of `AnalyzerNode` steps. The Architecture tab continues to work exactly as before from the user's perspective.

**Prerequisites:** [2026-04-02-c-pipeline-framework.md](2026-04-02-c-pipeline-framework.md) complete.

**Read for context:** Read all related documents before working on this plan: [b-unify-task-execution-engine.md](2026-04-02-b-unify-task-execution-engine.md), [c-pipeline-framework.md](2026-04-02-c-pipeline-framework.md), [e-plans-tab-migration.md](2026-04-02-e-plans-tab-migration.md), [f-claude-chain-migration.md](2026-04-02-f-claude-chain-migration.md), [g-pipeline-model-and-generic-ui.md](2026-04-02-g-pipeline-model-and-generic-ui.md)

**Prerequisites from g-doc (already complete):** `PipelineBlueprint`, `TaskSourceNode`, `PipelineModel`, and generic `PipelineView` are all implemented. This tab only needs to implement `buildPipeline()` on `ArchitecturePlannerService`, wire `ArchitecturePlannerModel` to `PipelineModel`, and update `ArchitecturePlannerDetailView`.

**Why Architecture tab first:** It has no `TaskSource`, no PR creation, and no markdown — purely sequential `AnalyzerNode` steps. Lowest risk first migration; validates that `AnalyzerNode` works end-to-end before the more complex tabs use it.

**Current use-case chain to migrate:**
1. `FormRequirementsUseCase` — extracts discrete requirements from a feature description
2. `CompileArchitectureInfoUseCase` — reads `ARCHITECTURE.md` from the target repo
3. `PlanAcrossLayersUseCase` — maps requirements → `ImplementationComponent` per layer
4. `ExecuteImplementationUseCase` — evaluates components against guidelines; records decisions and unclear flags
5. `ScoreConformanceUseCase` — scores each component-guideline pairing (0–100)
6. `GenerateReportUseCase` — produces the final conformance report

**Key files:**
- `Sources/Features/ArchitecturePlannerFeature/usecases/` — all 6 use cases above
- `Sources/Features/ArchitecturePlannerFeature/ArchitecturePlannerModels.swift` — SwiftData models (`PlanningJob`, `Requirement`, `Guideline`, `ImplementationComponent`, etc.)
- `Sources/Apps/AIDevToolsKitMac/Models/ArchitecturePlannerModel.swift`
- `Sources/Apps/AIDevToolsKitMac/Views/ArchitecturePlannerView.swift`, `ArchitecturePlannerDetailView.swift`, `GuidelineBrowserView.swift`

---

## - [ ] Phase 1: Map Use Cases to AnalyzerNode Types

Audit each of the 6 use cases and document its `AnalyzerNode<Input, Output>` signature. Deliverable: a table with columns: **Use case**, **Input type**, **Output type**, **SwiftData models written**, **Notes**.

Items to determine:
- What data flows between nodes? (Are intermediate types already defined in `ArchitecturePlannerModels.swift`, or do new types need to be created?)
- Which nodes write to SwiftData? (These save results in the service layer, not inside the node itself)
- `CompileArchitectureInfoUseCase` reads from disk — does this become an `AnalyzerNode` or a setup step in the service before the pipeline starts?
- `ExecuteImplementationUseCase` may internally loop over components — confirm whether this maps to one node or multiple

## - [ ] Phase 2: Implement ArchitecturePlannerService with buildPipeline()

Create `ArchitecturePlannerService` in `ArchitecturePlannerFeature`.

**Pattern established in g-doc:** The service's job is to *build* a `PipelineBlueprint`, not to run it. `PipelineModel` runs the blueprint via `PipelineRunner`. The service does not call `PipelineRunner` directly.

Tasks:
- Implement the `AnalyzerNode` types from Phase 1's table
- `ArchitecturePlannerService` takes: feature description, target repo path, active guideline set
- Service reads `ARCHITECTURE.md` before the pipeline starts (setup step in the service, not a node)
- Add `buildPipeline(options:) -> PipelineBlueprint`:
  - Assembles nodes: `[RequirementsNode, LayerMappingNode, EvaluationNode, ScoringNode, ReportNode]`
  - `initialNodeManifest` is the static list of these 5 node names — known upfront, no markdown pre-read needed
  - `PipelineConfiguration` carries `workingDirectory`, provider, no `betweenTasks` needed
  - Returns the blueprint; does not run it
- SwiftData saves happen in response to `PipelineEvent.nodeCompleted` in `ArchitecturePlannerModel` (not inside nodes or the service) — pipeline nodes are stateless
- The existing 6 use cases are deleted or deprecated once the service is verified

## - [ ] Phase 3: Wire ArchitecturePlannerModel to PipelineModel

Replace the existing use-case orchestration in `ArchitecturePlannerModel` with `ArchitecturePlannerService` + `PipelineModel`.

**Pattern established in g-doc:** The tab model owns a `PipelineModel` instance. It calls `service.buildPipeline()` then `pipelineModel.run(blueprint:)`. SwiftData saves happen by subscribing to `pipelineModel.onEvent`.

Tasks:
- Add `let pipelineModel = PipelineModel()` as a stored property on `ArchitecturePlannerModel`
- `execute()` calls `service.buildPipeline(options:)` → `pipelineModel.run(blueprint:)`
- Subscribe to `pipelineModel.onEvent` to save SwiftData results after each `.nodeCompleted` event (service saves `PlanningJob` and related models at this point)
- All existing SwiftData-backed behaviors must still work: job persistence across app restarts, requirements list, guideline browser, conformance scores, follow-up items

Verify end-to-end: run a full Architecture job from the Mac app and confirm all steps complete with correct output.

## - [ ] Phase 4: Update Architecture Tab UI to PipelineView

`PipelineView` is already generic (from g-doc). Wire `ArchitecturePlannerDetailView` to it.

Tasks:
- Inject `architecturePlannerModel.pipelineModel` via `.environment(pipelineModel)` on `PipelineView`
- `PipelineView` automatically renders the node list (Requirements → Layer Mapping → Evaluation → Scoring → Report) with completion state and current-node progress — no Architecture-specific code in `PipelineView`
- Architecture-specific panels remain in `ArchitecturePlannerDetailView` as conditional extensions: requirements list, layer mapping view, guideline browser, conformance scores, unclear flags, follow-up items, report viewer — shown/hidden based on job state, not pipeline state
- `ArchitecturePlannerView` (sidebar + tab container) is unchanged
- `GuidelineBrowserView` continues to work as a standalone panel
- No `ChatMessagesView` needed for this tab (no streaming chat output)

Verify: Architecture tab renders correctly in `PipelineView`; all panels show the same data as before.
