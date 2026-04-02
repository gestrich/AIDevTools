## Architecture Tab — Pipeline Migration

**Parent doc:** [2026-04-02-b-unify-task-execution-engine.md](2026-04-02-b-unify-task-execution-engine.md)

**Goal:** Migrate the Architecture tab (`ArchitecturePlannerFeature`) to run on the shared `PipelineSDK`. Replace the current ad-hoc use-case chain with an `ArchitecturePlannerService` that assembles a pipeline of `AnalyzerNode` steps. The Architecture tab continues to work exactly as before from the user's perspective.

**Prerequisites:** [2026-04-02-c-pipeline-framework.md](2026-04-02-c-pipeline-framework.md) complete.

**Read for context:** Read all related documents before working on this plan: [b-unify-task-execution-engine.md](2026-04-02-b-unify-task-execution-engine.md), [c-pipeline-framework.md](2026-04-02-c-pipeline-framework.md), [e-plans-tab-migration.md](2026-04-02-e-plans-tab-migration.md), [f-claude-chain-migration.md](2026-04-02-f-claude-chain-migration.md)

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

## - [ ] Phase 2: Implement ArchitecturePlannerService

Create `ArchitecturePlannerService` in `ArchitecturePlannerFeature`.

Tasks:
- Implement the 6 `AnalyzerNode` types from Phase 1's table
- `ArchitecturePlannerService` takes: feature description, target repo path, active guideline set
- Service reads `ARCHITECTURE.md` before the pipeline starts (setup, not a node — or a node if Phase 1 determines otherwise)
- Service assembles pipeline: `[RequirementsNode → LayerMappingNode → EvaluationNode → ScoringNode → ReportNode]`
- After each node completes, service saves results to SwiftData (`PlanningJob` and related models) — pipeline nodes are stateless
- Service exposes progress events that mirror the existing `ArchitecturePlannerModel` state machine transitions
- The existing 6 use cases are deleted or deprecated once the service is verified

## - [ ] Phase 3: Wire ArchitecturePlannerModel to Service

Replace the existing use-case orchestration in `ArchitecturePlannerModel` with `ArchitecturePlannerService`.

Tasks:
- `ArchitecturePlannerModel` calls `ArchitecturePlannerService.run(options:onProgress:)` instead of invoking use cases directly
- Map service progress events to existing model state transitions (no UI changes yet)
- All existing SwiftData-backed behaviors must still work: job persistence across app restarts, requirements list, guideline browser, conformance scores, follow-up items

Verify end-to-end: run a full Architecture job from the Mac app and confirm all steps complete with correct output.

## - [ ] Phase 4: Update Architecture Tab UI to PipelineView

Replace `ArchitecturePlannerDetailView` with `PipelineView` configured for the Architecture pipeline.

Tasks:
- `PipelineView` renders the node list (Requirements → Layer Mapping → Evaluation → Scoring → Report) with completion state and current-node progress
- Architecture-specific panels appear as conditional extensions: requirements list, layer mapping view, guideline browser, conformance scores, unclear flags, follow-up items, report viewer
- `ArchitecturePlannerView` (sidebar + tab container) is unchanged
- `GuidelineBrowserView` continues to work as a standalone panel

Verify: Architecture tab renders correctly in `PipelineView`; all panels show the same data as before.
