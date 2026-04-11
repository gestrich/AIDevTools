# Architecture Planner Feature

The Architecture Planner takes a plain-English feature description and walks it through a 10-step pipeline that extracts requirements, maps them to the codebase's architecture, scores guideline conformance, simulates execution decisions, and produces a report with followup items.

It runs from both the CLI (`arch-planner`) and the Mac app.

## Layers

The feature spans three packages following the standard 4-layer architecture:

```
Apps/
  AIDevToolsKitCLI/        CLI commands (ArchPlanner*.swift)
  AIDevToolsKitMac/        SwiftUI views + @Observable model

Features/
  ArchitecturePlannerFeature/
    usecases/              11 use cases — all business logic

Services/
  ArchitecturePlannerService/
    ArchitecturePlannerModels.swift          SwiftData @Model classes
    ArchitecturePlannerStepDefinitions.swift Step enum
    ArchitecturePlannerStore.swift           Per-repo SQLite persistence
```

Dependencies flow downward: Apps -> Features -> Services. The CLI and Mac app share the same use cases.

## Data Models

All models are SwiftData `@Model` classes persisted to `~/.ai-dev-tools/{repo-name}/architecture-planner/store.sqlite`.

### PlanningJob (root aggregate)

The central model. Tracks a single planning run.

| Field | Purpose |
|-------|---------|
| `jobId` | UUID, unique |
| `repoName`, `repoPath` | Target repository |
| `currentStepIndex` | Tracks which step to run next |

Relationships (all cascade-delete):

- `request` -> `ArchitectureRequest` (the user's feature description)
- `requirements` -> `[Requirement]` (extracted by Claude)
- `implementationComponents` -> `[ImplementationComponent]` (planned by Claude)
- `processSteps` -> `[ProcessStep]` (one per pipeline step, tracks status)
- `followupItems` -> `[FollowupItem]` (deferred work)

### Guideline and GuidelineCategory

Guidelines are scoped to a `repoName` (shared across jobs for that repo). Each guideline has:

- `title`, `body` (full text), `highLevelOverview` (one-liner)
- `filePathGlobs`, `descriptionMatchers` (matching criteria)
- `goodExamples`, `badExamples`
- `categories` (many-to-many with `GuidelineCategory`)
- `mappings` (one-to-many with `GuidelineMapping`)

### ImplementationComponent

A discrete unit of work in the plan. Produced by the Plan Across Layers step.

- `summary`, `details`, `filePaths`
- `layerName`, `moduleName` (where it lives in the architecture)
- `phaseNumber` (execution ordering)
- `requirements` (many-to-many back-link)
- `guidelineMappings` -> `[GuidelineMapping]` (conformance scores)
- `unclearFlags` -> `[UnclearFlag]` (ambiguities found during execution)
- `phaseDecisions` -> `[PhaseDecision]` (decisions recorded during execution)

### Supporting Models

| Model | Purpose |
|-------|---------|
| `GuidelineMapping` | Links a guideline to a component with `conformanceScore` (1-10), `matchReason`, `scoreRationale` |
| `ProcessStep` | One step in the 10-step flow. Fields: `stepIndex`, `name`, `status` (pending/active/completed/stale), `summary` |
| `PhaseDecision` | A decision made during execution: `guidelineTitle`, `decision`, `rationale`, `wasSkipped` |
| `UnclearFlag` | An ambiguity flagged during execution: `guidelineTitle`, `ambiguityDescription`, `choiceMade`, `isPromotedToFollowup` |
| `FollowupItem` | Deferred work or open question: `summary`, `details`, `isResolved` |

## The 10-Step Pipeline

Defined by the `ArchitecturePlannerStep` enum. Steps advance sequentially via `job.currentStepIndex`.

| # | Step | Use Case | Claude? |
|---|------|----------|---------|
| 0 | Describe Feature | (stores the request) | No |
| 1 | Form Requirements | `FormRequirementsUseCase` | Yes |
| 2 | Compile Architecture Info | `CompileArchitectureInfoUseCase` | Yes |
| 3 | Plan Across Layers | `PlanAcrossLayersUseCase` | Yes |
| 4 | Checklist Validation | `ChecklistValidationUseCase` | No |
| 5 | Build Implementation Model | `ScoreConformanceUseCase` | Yes |
| 6 | Review Implementation Plan | (auto-approves currently) | No |
| 7 | Execute Implementation | `ExecuteImplementationUseCase` | Yes |
| 8 | Final Report | `GenerateReportUseCase` | No |
| 9 | Compile Followups | `CompileFollowupsUseCase` | Yes |

### Step details

**Step 0 — Describe Feature:** The user provides a feature description. `CreatePlanningJobUseCase` stores it as an `ArchitectureRequest` and marks the step completed.

**Step 1 — Form Requirements:** Claude extracts discrete requirements from the feature description. Each becomes a `Requirement` record with `summary`, `details`, and `sortOrder`.

**Step 2 — Compile Architecture Info:** Reads `ARCHITECTURE.md` from the repo path (if it exists) and loads all guidelines from SwiftData. Sends both to Claude to identify relevant layers and applicable guidelines. The result is stored as a layers summary in the `ProcessStep`.

**Step 3 — Plan Across Layers:** Claude decomposes requirements into `ImplementationComponent` records, each placed in a specific `layerName`/`moduleName`. Claude also returns `guidelinesApplied` per component, which are matched by title to create `GuidelineMapping` records.

**Step 4 — Checklist Validation:** Synchronous (no Claude). Checks that all requirements are covered by at least one component and that components have guideline mappings.

**Step 5 — Score Conformance:** Claude scores each component against applicable guidelines on a 1-10 scale. Updates `GuidelineMapping.conformanceScore` and `scoreRationale`.

**Step 6 — Review Implementation Plan:** Placeholder for interactive approval. Currently auto-advances.

**Step 7 — Execute Implementation:** Groups components by `phaseNumber` and evaluates each phase against guidelines. Claude returns `PhaseDecision` records (what was decided and why) and `UnclearFlag` records (ambiguities encountered).

**Step 8 — Final Report:** Synchronous. Generates a markdown report from all accumulated data (requirements, components, mappings, decisions, flags, followups).

**Step 9 — Compile Followups:** Two phases: (1) promotes unpromoted `UnclearFlag` records to `FollowupItem` records, then (2) Claude identifies additional deferred work (skipped implementations, missing tests, integration needs, etc.).

## Guideline System

Guidelines provide the architectural knowledge that Claude uses throughout the pipeline.

### Seeding

`SeedGuidelinesUseCase` populates guidelines when the first job is created for a repo. It is idempotent — if any guidelines exist for the repo, it skips. Sources:

1. **`ARCHITECTURE.md`** from the repo path (optional — skipped if the file doesn't exist)
2. **6 bundled swift-architecture guidelines** — 4-layer overview, layer placement rules, architecture principles, creating features, configuration/data paths, code style conventions
3. **8 bundled swift-swiftui guidelines** — Model-View pattern, enum-based state, model composition, dependency injection, view vs model state, view identity, model scalability, data models

The bundled guidelines are embedded as string constants in `SeedGuidelinesUseCase.GuidelineDefinition` structs. They are static snapshots of the `swift-architecture` and `swift-swiftui` skill content and do not auto-update when those skills change.

### How guidelines flow through the pipeline

Guidelines are loaded from SwiftData and included in Claude prompts at several steps. Currently, only the `title` and `highLevelOverview` (one-liner) are sent to Claude in steps 2, 3, and 7. The full `body` is sent in step 5 (Score Conformance), truncated to 200 characters per guideline.

| Step | What Claude receives |
|------|---------------------|
| Compile Architecture Info | `title` + `highLevelOverview` |
| Plan Across Layers | `title` + `highLevelOverview` |
| Score Conformance | `title` + first 200 chars of `body` |
| Execute Implementation | `title` + `highLevelOverview` |
| Compile Followups | (no guidelines in prompt — works from accumulated data) |

Guidelines can also be managed manually via CLI:
- `arch-planner guidelines list` — list all for a repo
- `arch-planner guidelines add` — add a custom guideline
- `arch-planner guidelines delete` — remove a guideline
- `arch-planner guidelines seed` — re-seed from bundled content

## Claude Integration

All AI-powered steps use `ClaudeCLIClient` from the `ClaudeCLISDK` package. The pattern is consistent:

1. Build a prompt with context (requirements, ARCHITECTURE.md, guidelines, components)
2. Define a JSON schema for the expected response structure
3. Call `claudeClient.runStructured(ResponseType.self, command:, workingDirectory:, onFormattedOutput:)`
4. Parse the structured response into SwiftData records

The `onFormattedOutput` callback streams Claude's formatted output in real-time. The CLI prints it inline; the Mac app shows it in a live output panel.

All Claude calls use `streamJSON` output format with structured JSON schemas, `printMode = true`, and `verbose = true`.

## CLI Commands

Entry point: `ArchPlannerCommand` with subcommands:

| Command | Purpose |
|---------|---------|
| `arch-planner create` | Create a new planning job |
| `arch-planner update --step <name>` | Run a specific step (`--step next` for auto-advance, `--step all` to run remaining steps) |
| `arch-planner inspect` | List jobs or show job details |
| `arch-planner report` | Generate markdown report |
| `arch-planner delete` | Delete a planning job |
| `arch-planner guidelines <sub>` | Manage guidelines (list, add, delete, seed) |

`ArchPlannerUpdateCommand` is the main workhorse — it dispatches to the correct use case based on `--step` and wires up progress and output callbacks.

## Mac App

`ArchitecturePlannerModel` is a `@MainActor @Observable` class that:

- Holds all 9 use cases as dependencies (injected via init with defaults)
- Manages state via `enum State { case idle, loading, running(stepName:), error(Error) }`
- Accumulates streamed Claude output in `currentOutput` for the live output panel
- Exposes `loadJobs()`, `createJob()`, `runNextStep()`, `deleteJob()`, `goToStep()`, `generateReport()`

The UI is split across two views:

- **`ArchitecturePlannerView`** — sidebar with job list + creation form, detail area
- **`ArchitecturePlannerDetailView`** — step navigation bar, step detail content, live output panel (visible while running), components sidebar showing implementation components by layer

## Persistence

`ArchitecturePlannerStore` wraps a SwiftData `ModelContainer` configured with all 11 model types. Each repo gets its own SQLite database at:

```
~/.ai-dev-tools/{repo-name}/architecture-planner/store.sqlite
```

The store is created lazily — `ArchitecturePlannerStore(repoName:)` creates the directory and database if they don't exist. All data access goes through `store.createContext()` which returns a fresh `ModelContext` on the main actor.
