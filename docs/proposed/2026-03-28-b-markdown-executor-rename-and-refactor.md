## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture (Apps, Features, Services, SDKs), layer placement rules, use case patterns, `@Observable` conventions |

## Background

The current "Plan Runner" feature generates phased markdown plans and executes them via AI. It's being renamed to **Markdown Planner** to better describe what it does, and refactored to:

1. **Remove dynamic phase generation** — currently Phases 1-3 are scaffolding and Phase 3 generates the real phases at runtime. Instead, generation should produce a complete plan upfront so the user can review all phases before execution.
2. **Adopt plan skill conventions** — the plan generation prompt should follow the same structure as `gestrich-claude-tools-plan`: skill discovery from CLAUDE.md, relevant skills table, detailed phases with "Skills to read" sections, ≤10 phases, validation phase.
3. **Adopt execution skill conventions** — phase execution should follow `gestrich-claude-tools-next-task`: check uncommitted changes, read listed skills, completion notes with skills used, commit per phase.
4. **Add provider selection** — Mac app provider picker and CLI `--provider` flag.
5. **Support execute-next vs execute-all** — run one phase or all remaining.

See [architecture-planner-vs-plans-evaluation.md](architecture-planner-vs-plans-evaluation.md) for the full feature comparison that motivated this refactor.

## - [x] Phase 1: Rename PlanRunner to MarkdownPlanner across all layers

**Skills used**: `swift-architecture`
**Principles applied**: Mechanical rename across all 4 layers (Apps, Features, Services, SDKs) preserving existing architecture

**Skills to read**: `swift-architecture`

Rename all types, files, targets, and module references from `PlanRunner` to `MarkdownPlanner`. This is a mechanical rename with no behavior changes.

**Files to rename:**
- Features: `PlanRunnerFeature/` → `MarkdownPlannerFeature/` (all 6 use cases, 2 service files)
- Services: `PlanRunnerService/` → `MarkdownPlannerService/` (4 files: `PlanRepoSettings`, `PlanRepoSettingsStore`, `PlanEntry`, `ArchitectureDiagram`)
- CLI: `PlanRunnerCommand.swift`, `PlanRunnerPlanCommand.swift`, `PlanRunnerExecuteCommand.swift`, `PlanRunnerDeleteCommand.swift` → `MarkdownPlanner*` equivalents
- Mac: `PlanRunnerModel.swift` → `MarkdownPlannerModel.swift`, `PlanDetailView.swift` → `MarkdownPlannerDetailView.swift`

**Type renames:**
- `PlanRunnerFeature` target → `MarkdownPlannerFeature`
- `PlanRunnerService` target → `MarkdownPlannerService`
- `PlanRepoSettings` → `MarkdownPlannerRepoSettings`
- `PlanRepoSettingsStore` → `MarkdownPlannerRepoSettingsStore`
- `PlanEntry` → `MarkdownPlanEntry`
- CLI command `plan-runner` → `markdown-planner`

**Also update:**
- `Package.swift` targets and dependencies
- All `import PlanRunnerFeature` / `import PlanRunnerService` statements
- Logger labels
- Any references in tests

**Expected outcome:** `swift build` passes, all tests pass, no remaining references to `PlanRunner` in source code.

## - [x] Phase 2: Rewrite plan generation to produce complete plans

**Skills used**: `swift-architecture`
**Principles applied**: Rewrote AI prompt to produce complete plans upfront (no dynamic phase generation). Added CLAUDE.md reading for skill discovery. Added YYYY-MM-DD-alpha filename convention. Removed architecture diagram generation from plan step.

**Skills to read**: `swift-architecture`

Replace the current 3-phase scaffold generation in `GeneratePlanUseCase` (being renamed to `GenerateMarkdownPlanUseCase`) with a single AI call that produces a complete, detailed plan.

The generation prompt must produce plans matching this structure:
- **Relevant Skills** table — only skills relevant to the task, discovered by reading the target repo's CLAUDE.md
- **Background** section — why we're making changes, user requirements
- **All phases** (Phase 1 through N, ≤10 total), each with:
  - `**Skills to read**: skill-a, skill-b` listing which skills the executor should read before implementing
  - Detailed description: specific tasks, files to modify, technical considerations, expected outcomes
- **Final phase is always Validation** — automated testing preferred over manual verification
- Filename format: `YYYY-MM-DD-<alpha>-<description>.md` using the alpha-index convention

The prompt should include:
- The user's request text
- Repository context (path, description, skills list, architecture docs, verification commands, PR settings, GitHub user)
- The repo's CLAUDE.md content (so the AI can discover skills)
- Instructions to read skill descriptions and determine which are relevant
- Scope/sizing rules: stay focused on exactly what was requested, ≤10 phases, scale phases to match request size

Remove the `architectureJSONInstruction` method and architecture diagram generation from the generation step — that complexity can be revisited later.

**Expected outcome:** Generated plans have all phases visible for user review. No Phase 3 dynamically creates more phases. Plans include relevant skills table and "Skills to read" per phase.

## - [x] Phase 3: Enhance phase execution with skill loading and completion notes

**Skills used**: `swift-architecture`
**Principles applied**: Added git status check at SDK layer (GitClient.status), skill parsing at Feature layer, and completion notes instructions in execution prompt. Progress enum extended for uncommitted changes notification.

**Skills to read**: `swift-architecture`

Update `ExecuteMarkdownPlanUseCase` to follow `gestrich-claude-tools-next-task` conventions:

**Before execution starts:**
- Run `git status --porcelain` via `GitClient` to check for uncommitted changes
- Add a new `Progress` case (e.g., `.uncommittedChanges(files: [String])`) so the app/CLI can warn the user
- If uncommitted changes exist, report them but proceed (the caller decides whether to stop)

**Per-phase execution prompt changes:**
- Parse the phase's markdown content to extract any `**Skills to read**: ...` line
- Include the skill names in the execution prompt so the AI knows to read them
- After phase completes, update the markdown with completion notes:
  ```
  ## - [x] Phase 2: Implement command parsing

  **Skills used**: `swift-testing`, `design-kit`
  **Principles applied**: [Brief note from AI about key decisions]
  ```

**Commit format per phase:**
```
Complete Phase N: [Description]
```

**Expected outcome:** Each executed phase reads relevant skills, adds completion notes to the markdown, and commits with a descriptive message.

## - [x] Phase 4: Add execute-next-only mode

**Skills used**: `swift-architecture`
**Principles applied**: ExecuteMode enum at Feature layer, --next CLI flag, "Next only" checkbox toggle in Mac detail view. Apps layer owns UI state, Features layer owns the mode logic.

**Skills to read**: `swift-architecture`

Add support for executing only the next incomplete phase instead of all remaining phases.

**Changes to `ExecuteMarkdownPlanUseCase`:**
- Add `executeMode: ExecuteMode` to `Options` where `ExecuteMode` is an enum: `.next` or `.all`
- In `.next` mode: execute one phase, commit, return result with `phasesExecuted: 1`
- In `.all` mode: current loop behavior (execute all remaining)

**Changes to CLI (`MarkdownPlannerExecuteCommand`):**
- Add `--next` flag (default: execute all)
- When `--next` is passed, set `executeMode: .next`

**Changes to Mac app (`MarkdownPlannerModel`):**
- Add a toggle or segmented control for "Next phase" vs "All phases"
- Wire the selection to the use case options

**Expected outcome:** User can run one phase at a time for review, or batch-execute all remaining.

## - [x] Phase 5: Add provider selection

**Skills used**: `swift-architecture`
**Principles applied**: Followed ArchitecturePlannerModel pattern for provider picker. CLI execute already had --provider; added to plan command. Mac model accepts ProviderRegistry via constructor injection, stores selectedProviderName with didSet rebuild.

**Skills to read**: `swift-architecture`

Add AI provider selection to both CLI and Mac app. Follow the same pattern already used by Architecture Planner for provider selection.

**CLI (`MarkdownPlannerExecuteCommand` and `MarkdownPlannerPlanCommand`):**
- Add `--provider <name>` option
- Resolve the provider from the registered providers list
- Pass to the use case's `AIClient`

**Mac app (`MarkdownPlannerModel`):**
- Add a provider picker (dropdown) — reuse the same pattern from `ArchitecturePlannerModel`
- Rebuild use cases when provider changes
- Persist selection per session (not across app launches)

**Expected outcome:** Users can choose which AI provider to use for both plan generation and execution, from both CLI and Mac app.

## - [x] Phase 6: Validation

**Skills used**: `swift-architecture`
**Principles applied**: Verified swift build passes, all 37 MarkdownPlanner tests pass, no PlanRunner references remain in Swift source.

**Skills to read**: `swift-architecture`

Verify the refactor works end-to-end:

- `swift build` passes with no errors or warnings related to the rename
- All existing `PlanRunner` tests pass under new names
- CLI commands work:
  - `markdown-planner plan "add a new feature"` generates a complete plan with all phases
  - `markdown-planner execute --next` runs one phase
  - `markdown-planner execute` runs all remaining phases
  - `markdown-planner execute --provider <name>` uses the specified provider
  - `markdown-planner delete` deletes a plan
- Mac app:
  - Plans list loads
  - Provider picker appears and is functional
  - Execute next / execute all toggle works
  - Phase completion notes appear in markdown after execution
- No remaining references to `PlanRunner` in source code (grep to confirm)
- Verify phase execution uses fresh AI context per phase (no conversation bleed)
