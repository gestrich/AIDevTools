## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer Swift app architecture (Apps, Features, Services, SDKs) — also the seed content for architecture guidelines |
| `swift-app-architecture:swift-swiftui` | SwiftUI Model-View patterns — also seed content for SwiftUI guidelines |
| `ai-dev-tools-debug` | Debugging guide for AIDevTools CLI and Mac app |

## Background

The Architecture Planner feature (spec: `2026-03-22-h-plan-runner-v2-architecture-driven-flow.md`) was implemented as a structural skeleton — all SwiftData models, use case files, CLI commands, and Mac app views exist and compile. However, an audit revealed that the **logic inside the use cases is incomplete**, the **guideline pipeline is entirely missing** (nothing seeds or reads guidelines), the **CLI `update` command only covers 3 of 10 steps**, and key interactive features like **approve/revise loops** are absent.

This plan addresses the gaps needed to make the feature work end-to-end via the CLI. The goal is: run every step in sequence via CLI commands against this repo and produce a complete report.

The original spec doc has been annotated with a detailed audit table showing what's done and what remains.

## Phases

## - [x] Phase 1: Seed Guidelines from Skills and ARCHITECTURE.md

**Skills to read**: `swift-app-architecture:swift-architecture`, `swift-app-architecture:swift-swiftui`

The entire guideline pipeline is empty — nothing populates the SwiftData guideline store. This phase fills it.

- Read the `swift-architecture` skill content and transform it into guidelines with categories like `architecture`, `layer-placement`, `conventions`
- Read the `swift-swiftui` skill content and transform it into guidelines with categories like `swiftui`, `observable-model`, `view-patterns`
- Add a `SeedGuidelinesUseCase` in ArchitecturePlannerFeature that:
  - Reads `ARCHITECTURE.md` from the repo path (if it exists) and creates a guideline from it
  - Creates guidelines from bundled skill content (embedded as string constants or read from files in this repo)
  - Skips seeding if guidelines already exist for the repo (idempotent)
  - Each guideline should have: title, body, highLevelOverview, filePathGlobs (where applicable), categories
- Add a CLI command: `arch-planner guidelines seed --repo-name NAME --repo-path PATH`
- Call `SeedGuidelinesUseCase` automatically in `CreatePlanningJobUseCase` so new jobs start with guidelines populated
- Verify: `arch-planner guidelines list --repo-name AIDevTools` shows seeded guidelines

**Completed.** Technical notes:
- `SeedGuidelinesUseCase` created with 15 bundled guidelines: 1 from ARCHITECTURE.md (if present), 6 from swift-architecture skill, 8 from swift-swiftui skill
- Guidelines are embedded as string constants in `SeedGuidelinesUseCase.GuidelineDefinition` structs — no external file reads needed at runtime
- Categories seeded: `architecture`, `conventions`, `layer-placement`, `observable-model`, `swiftui`, `view-patterns`
- Idempotent: skips seeding if any guidelines already exist for the repo
- `CreatePlanningJobUseCase` calls `SeedGuidelinesUseCase` automatically before creating the job
- `GuidelinesSeedCommand` added as `arch-planner guidelines seed --repo-name NAME --repo-path PATH`

## - [x] Phase 2: Fix CompileArchitectureInfoUseCase to Use Real Data

The current implementation sends a generic prompt without reading any actual files. Fix it to:

- Read `ARCHITECTURE.md` from `repoPath` and include its content in the prompt
- Load guidelines from the SwiftData store (now populated by Phase 1) and include their high-level overviews in the prompt
- The prompt should ask Claude to identify which layers are relevant to the requirements and which guidelines apply
- Store the layers summary in the ProcessStep
- Verify: `arch-planner update --step compile-arch-info` produces output that references real layers from ARCHITECTURE.md

**Completed.** Technical notes:
- `CompileArchitectureInfoUseCase` now reads `ARCHITECTURE.md` from the repo path and includes its full content in the prompt (wrapped in `<architecture-document>` tags)
- Falls back gracefully if `ARCHITECTURE.md` doesn't exist at the repo path
- Guidelines loaded from SwiftData are included with titles and high-level overviews
- Prompt restructured into sections (ARCHITECTURE.md, Requirements, Loaded Guidelines, Task) and asks Claude to reference actual layer names, guideline titles, and conventions
- ProcessStep summary now stores the full layers summary instead of truncating to 200 characters

## - [x] Phase 3: Fix PlanAcrossLayersUseCase to Include Guidelines

The current implementation creates components without real guideline context. Fix it to:

- Include loaded guidelines (titles + overviews) in the prompt so Claude can reference them when deciding layer placement
- Include ARCHITECTURE.md content so Claude knows the actual layer structure
- The prompt should ask Claude to explain which guidelines influenced each placement decision
- Verify: `arch-planner update --step plan-across-layers` creates components that reference real layers and guidelines

**Completed.** Technical notes:
- Guidelines loaded from SwiftData store and included as titles + high-level overviews in the prompt
- ARCHITECTURE.md read from repo path and included in `<architecture-document>` tags (with graceful fallback if missing)
- Prompt restructured into sections (ARCHITECTURE.md, Architecture Analysis, Requirements, Architectural Guidelines, Task)
- Added `GuidelineReference` DTO (title + reason) and `guidelinesApplied` field to `ComponentDTO` so Claude reports which guidelines influenced each component
- `GuidelineMapping` records created automatically linking each component to its referenced guidelines via case-insensitive title matching
- JSON schema updated to require `guidelinesApplied` array on each component

## - [x] Phase 4: Complete the CLI `update` Command for All Steps

`ArchPlannerUpdateCommand` only handles 3 steps. Add the remaining:

- `score` — call ScoreConformanceUseCase
- `checklist-validation` — call ScoreConformanceUseCase (this is the same step in the current mapping, or create a dedicated ChecklistValidationUseCase if distinct logic is needed)
- `build-implementation-model` — call ScoreConformanceUseCase (current mapping) or adjust if Phase 5 changes this
- `execute` — call ExecuteImplementationUseCase
- `report` — call GenerateReportUseCase
- `followups` — create and store FollowupItems from the job's unclear flags and open questions
- `next` — auto-advance to the correct next step based on `job.currentStepIndex` (currently hardcoded to `form-requirements`)
- Verify: `arch-planner update --step next` advances through every step in sequence

**Completed.** Technical notes:
- `ArchPlannerUpdateCommand` now handles all 10 steps: `form-requirements`, `compile-arch-info`, `plan-across-layers`, `checklist-validation`, `build-implementation-model`/`score`, `review-implementation-plan`, `execute`, `report`, `followups`, plus `next`
- `next` resolves `job.currentStepIndex` to a step via `ArchitecturePlannerStep.cliName` and dispatches to the matching handler
- `ChecklistValidationUseCase` created for step 4 — validates that requirements are covered by components and components have guideline mappings
- `CompileFollowupsUseCase` created for step 9 — promotes `UnclearFlag` records to `FollowupItem` entries (idempotent via `isPromotedToFollowup`)
- `review-implementation-plan` (step 6) auto-completes with a summary noting interactive review is not yet implemented
- `GenerateReportUseCase` fixed to advance `currentStepIndex` to the followups step after completing
- `ArchitecturePlannerStep` gained `cliName` property and `fromCLIName(_:)` factory for CLI ↔ step resolution

## - [x] Phase 5: Fix ExecuteImplementationUseCase to Record Real Decisions

The current implementation records stub PhaseDecisions ("Implemented as planned"). Fix it to:

- Include applicable guidelines for each component in the prompt to Claude
- Parse Claude's response to extract actual decisions (what was done, what was skipped, which guideline drove it)
- Store real PhaseDecision records with: guidelineTitle, decision, rationale, phaseNumber, wasSkipped
- Create UnclearFlag records when Claude indicates a guideline was ambiguous
- This step doesn't need to execute actual code changes yet (that's a future enhancement) — but the decision recording should be real, not stubbed

**Completed.** Technical notes:
- Replaced unstructured `claudeClient.run()` call with `claudeClient.runStructured()` using a JSON schema that returns `decisions` and `unclearFlags` arrays
- `DecisionDTO` captures: componentIndex, guidelineTitle, decision, rationale, wasSkipped — mapped to real `PhaseDecision` records per component
- `UnclearFlagDTO` captures: componentIndex, guidelineTitle, ambiguityDescription, choiceMade — mapped to `UnclearFlag` records per component
- Guidelines loaded from SwiftData store and included in the prompt so Claude references real guideline titles
- Prompt restructured to ask Claude to evaluate implementation decisions against guidelines rather than execute code
- Step summary now includes unclear flag count alongside phase and decision counts
- Removed `dangerouslySkipPermissions` since structured JSON output doesn't execute code

## - [x] Phase 6: Implement Followups Step

The FollowupItem model exists but nothing creates followup items. Add:

- A `CompileFollowupsUseCase` that:
  - Collects all UnclearFlags from the job's implementation components
  - Promotes flagged items to FollowupItem records
  - Uses Claude to identify any additional deferred work based on the implementation plan
  - Stores FollowupItems in the job
- Wire into `runNextStep` in the model (currently `break`s for `.followups`)
- Add to CLI `update` command as `--step followups`
- Mark the ProcessStep as completed

**Completed.** Technical notes:
- `CompileFollowupsUseCase` enhanced with Claude integration via `runStructured()` to identify additional deferred work (skipped implementations, integration verification needs, missing tests/docs, performance considerations, external dependencies)
- Added `repoPath` to `Options` since Claude client needs a working directory
- Two-phase followup collection: first promotes unpromoted `UnclearFlag` records to `FollowupItem`, then calls Claude with the full implementation plan to identify additional deferred work
- Claude response parsed via `FollowupsResponse` DTO containing `additionalFollowups` array of `FollowupDTO` (summary + details)
- `currentStepIndex` now advanced past the last step (followups.rawValue + 1) to mark the job as fully complete
- `ArchitecturePlannerModel` (MacApp) wired to call `CompileFollowupsUseCase` instead of `break` for `.followups`
- Added `compileFollowupsUseCase` as an injected dependency in `ArchitecturePlannerModel`
- CLI progress reporting updated with new `.identifyingDeferredWork` and `.identified(count:)` progress states

## - [x] Phase 7: End-to-End CLI Validation

**Skills to read**: `ai-dev-tools-debug`

Run the full flow via CLI against this repo (AIDevTools) and verify every step succeeds:

```bash
# 1. Seed guidelines
arch-planner guidelines seed --repo-name AIDevTools --repo-path .

# 2. Verify guidelines exist
arch-planner guidelines list --repo-name AIDevTools

# 3. Create a job
arch-planner create --repo-name AIDevTools --repo-path . "Add a settings toggle for architecture planner guideline auto-seeding"

# 4. Run each step in sequence
arch-planner update --repo-name AIDevTools --repo-path . --job-id <id> --step form-requirements
arch-planner update --repo-name AIDevTools --repo-path . --job-id <id> --step compile-arch-info
arch-planner update --repo-name AIDevTools --repo-path . --job-id <id> --step plan-across-layers
arch-planner update --repo-name AIDevTools --repo-path . --job-id <id> --step checklist-validation
arch-planner update --repo-name AIDevTools --repo-path . --job-id <id> --step build-implementation-model
arch-planner update --repo-name AIDevTools --repo-path . --job-id <id> --step score
arch-planner update --repo-name AIDevTools --repo-path . --job-id <id> --step execute
arch-planner update --repo-name AIDevTools --repo-path . --job-id <id> --step report
arch-planner update --repo-name AIDevTools --repo-path . --job-id <id> --step followups

# 5. Inspect final state
arch-planner inspect --repo-name AIDevTools --job-id <id>

# 6. Generate report
arch-planner report --repo-name AIDevTools --job-id <id>
```

Success criteria:
- Every step completes without error
- `inspect` shows all 10 steps as completed
- Requirements, components, guideline mappings, conformance scores, decisions, and followups are all populated
- The report includes real content at every section (not empty/placeholder)
- Guidelines referenced in the report match real guidelines from the seeded set

**Completed.** Technical notes:
- Full end-to-end flow validated against AIDevTools repo with feature request "Add a settings toggle for architecture planner guideline auto-seeding"
- 14 guidelines seeded (6 architecture, 8 SwiftUI)
- All 10 steps completed without errors: describe-feature, form-requirements, compile-arch-info, plan-across-layers, checklist-validation, build-implementation-model, review-implementation-plan, execute, report, followups
- Results: 8 requirements extracted, 4 implementation components planned, 19 guideline mappings scored (avg 7.9/10), 19 phase decisions recorded, 3 unclear flags identified, 8 followup items compiled
- Report contains real content in every section with specific guideline references, conformance scores with rationale, tradeoff analysis, and implementation decisions
- `score` step is an alias for `build-implementation-model` (both run the same scoring logic)
- `review-implementation-plan` auto-approves since interactive review is not yet implemented
- No code changes required — this phase was purely validation of the existing implementation from Phases 1-6
