> **2026-03-29 Obsolescence Evaluation:** Obsolete. This refactoring was already completed in "2026-03-28-b-markdown-executor-rename-and-refactor.md" but renamed to "MarkdownPlanner" instead of "MarkdownExecutor". The same goals were achieved: dynamic phase generation removed, skill conventions adopted, provider selection added, and execute-next vs execute-all support.

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture (Apps, Features, Services, SDKs) and placement rules |
| `gestrich-claude-tools-plan` | Plan creation conventions: skill discovery, phase structure, naming, detail level |
| `gestrich-claude-tools-next-task` | Phase execution conventions: uncommitted change check, skill reading, review cycles, commit format |

## Background

The current "Plan Runner" feature does two things:

1. **Generates** a markdown plan from a natural language description
2. **Executes** each phase of a markdown plan using AI

The name "Plan Runner" is vague. The feature is really a **Markdown Executor** — it takes a markdown document with phased checkboxes and drives an AI through each phase. The generation step is just a convenience to produce that markdown.

Additionally, the current plan generation has a problematic design: Phases 1-3 are hardcoded scaffolding where Phase 3 dynamically generates the remaining phases at execution time. This means:
- The user can't review the full plan before execution starts
- The first 3 phases are always the same boilerplate
- Phase 3's dynamic generation is fragile and couples generation with execution

The refactor replaces this with a simpler model: generation produces a **complete, detailed plan** upfront (following the same conventions as the `gestrich-claude-tools-plan` skill), and execution just walks through those phases one at a time.

### What Changes

- **Rename**: `PlanRunner` → `MarkdownExecutor` across all layers (Feature, Service, CLI, Mac app)
- **Simplify generation**: Produce a full plan with all phases upfront — no dynamic phase creation during execution
- **Adopt skill conventions**: Plan generation mirrors `gestrich-claude-tools-plan` (skill discovery from CLAUDE.md, relevant skills table, detailed phases with "Skills to read" sections, ≤10 phases, validation phase)
- **Adopt execution conventions**: Phase execution mirrors `gestrich-claude-tools-next-task` (check uncommitted changes, read listed skills before implementing, mark complete with skills-used notes, commit per phase)
- **New AI context per phase**: Each phase execution gets its own AI conversation context (already the case with `runStructured` calls, but make this explicit and ensure no context bleed)
- **Provider selection**: Mac app gets a provider picker (already exists for Architecture Planner — reuse pattern); CLI gets `--provider` flag
- **Execute next vs execute all**: Support both "execute next phase only" and "execute all remaining phases" modes

### What Stays the Same

- Markdown format with `## - [ ] Phase N:` / `## - [x] Phase N:` checkboxes
- Per-repo proposed/completed directory settings (`PlanRepoSettings`)
- Phase logging to `~/.ai-dev-tools/{repo}/plan-logs/`
- Architecture diagram generation (when repo has ARCHITECTURE.md)
- Move-to-completed on full completion
- Toggle phase, delete plan, complete plan, load plans use cases

## Evaluation of Current vs Proposed

### Plan Generation: Current

The current `GeneratePlanUseCase` produces exactly 3 phases:
1. **Interpret the Request** — explore codebase at execution time
2. **Gather Architectural Guidance** — read skills/docs at execution time
3. **Plan the Implementation** — dynamically generate Phases 4-N at execution time

Problems:
- User can't see the real plan until after Phases 1-3 execute (which costs AI time and tokens)
- Phase 3 generates an unpredictable number of additional phases
- No skill discovery from CLAUDE.md — skills are passed as a flat list
- No "Skills to read" per phase — executor doesn't know which skills are relevant to each phase

### Plan Generation: Proposed

The new generation produces a **complete plan** upfront, following `gestrich-claude-tools-plan` conventions:

1. Read the project's CLAUDE.md to discover available skills
2. Read each skill's description to determine relevance
3. Generate a plan with:
   - **Relevant Skills** table (only skills relevant to this task)
   - **Background** section (why we're making changes, user requirements)
   - **All phases** (1 through N, ≤10), each with:
     - `**Skills to read**: skill-a, skill-b` section
     - Detailed description: specific tasks, files to modify, technical considerations, expected outcomes
   - **Validation phase** as the final phase (automated testing preferred)
4. Write to `docs/proposed/YYYY-MM-DD-<alpha>-<description>.md`

The AI does this in a single generation call. The user reviews the complete plan before any execution starts.

### Phase Execution: Current

The current `ExecutePlanUseCase`:
1. Asks AI to analyze the markdown and return phase statuses
2. Loops through pending phases, executing each with a generic prompt
3. Always executes all remaining phases (no "next only" mode)
4. No uncommitted change check before starting
5. No skill reading during phase execution
6. Minimal completion notes

### Phase Execution: Proposed

The new execution follows `gestrich-claude-tools-next-task` conventions:

**Before starting:**
- Check for uncommitted changes via `git status --porcelain`
- Warn or auto-commit if changes exist

**Per phase:**
1. Read the phase's "Skills to read" and load those skills into the AI prompt
2. Implement the phase's requirements
3. Mark the phase as complete with completion notes:
   ```
   ## - [x] Phase 2: Implement command parsing

   **Skills used**: `swift-testing`, `design-kit`
   **Principles applied**: Used factory pattern per design-kit conventions
   ```
4. Commit changes with format: `Complete Phase N: [Description]`

**Execution modes:**
- **Execute next**: Run only the next incomplete phase, then stop
- **Execute all**: Run all remaining phases sequentially (current behavior)

**Each phase gets a fresh AI context** — no conversation state carries between phases.

### Rename Scope

| Current Name | New Name |
|-------------|----------|
| `PlanRunnerFeature` | `MarkdownExecutorFeature` |
| `PlanRunnerService` | `MarkdownExecutorService` |
| `PlanRunnerModel` | `MarkdownExecutorModel` |
| `PlanRunnerCommand` | `MarkdownExecutorCommand` |
| `PlanDetailView` | `MarkdownExecutorDetailView` |
| `GeneratePlanUseCase` | `GenerateMarkdownPlanUseCase` |
| `ExecutePlanUseCase` | `ExecuteMarkdownPlanUseCase` |
| `LoadPlansUseCase` | `LoadMarkdownPlansUseCase` |
| `TogglePhaseUseCase` | `TogglePhaseUseCase` (unchanged — generic enough) |
| `CompletePlanUseCase` | `CompletePlanUseCase` (unchanged — generic enough) |
| `DeletePlanUseCase` | `DeletePlanUseCase` (unchanged — generic enough) |
| CLI: `plan-runner` | CLI: `markdown-executor` |
| `PlanRepoSettings` | `MarkdownExecutorRepoSettings` |
| `PlanRepoSettingsStore` | `MarkdownExecutorRepoSettingsStore` |
| `PlanEntry` | `MarkdownPlanEntry` |

### Files Affected

**Features Layer** (`PlanRunnerFeature` → `MarkdownExecutorFeature`):
- `usecases/GeneratePlanUseCase.swift` — rewrite generation prompt to match `gestrich-claude-tools-plan`
- `usecases/ExecutePlanUseCase.swift` — add uncommitted check, skill loading, completion notes, next-only mode
- `usecases/LoadPlansUseCase.swift` — rename
- `usecases/TogglePhaseUseCase.swift` — rename module import
- `usecases/CompletePlanUseCase.swift` — rename module import
- `usecases/DeletePlanUseCase.swift` — rename module import
- `services/PhaseStatus.swift` — rename module
- `services/ClaudeResponseModels.swift` — rename module

**Services Layer** (`PlanRunnerService` → `MarkdownExecutorService`):
- `PlanRepoSettings.swift` — rename
- `PlanRepoSettingsStore.swift` — rename
- `PlanEntry.swift` — rename
- `ArchitectureDiagram.swift` — rename module

**Apps Layer (CLI)**:
- `PlanRunnerCommand.swift` → `MarkdownExecutorCommand.swift` — rename, add `--provider` flag
- `PlanRunnerPlanCommand.swift` → `MarkdownExecutorPlanCommand.swift`
- `PlanRunnerExecuteCommand.swift` → `MarkdownExecutorExecuteCommand.swift` — add `--next` flag, `--provider` flag
- `PlanRunnerDeleteCommand.swift` → `MarkdownExecutorDeleteCommand.swift`

**Apps Layer (Mac)**:
- `Models/PlanRunnerModel.swift` → `Models/MarkdownExecutorModel.swift` — add provider picker state, next-only mode
- `Views/PlanDetailView.swift` → `Views/MarkdownExecutorDetailView.swift` — add provider picker UI, next/all toggle

**Package.swift**: Rename targets and dependencies

### Architecture Compliance

Following the 4-layer architecture:

| Layer | Responsibility | Changes |
|-------|---------------|---------|
| **Apps** | `@Observable` models, CLI commands, SwiftUI views, provider picker UI | Rename + add provider selection + next-only toggle |
| **Features** | Use cases: generate plan, execute phases, load/toggle/complete/delete | Rewrite generation prompt, enhance execution with skill loading |
| **Services** | `MarkdownExecutorRepoSettings`, `MarkdownPlanEntry`, settings store | Rename |
| **SDKs** | `AIClient`, `GitClient` (unchanged) | No changes |

Dependencies flow downward only. No new cross-feature dependencies introduced.
