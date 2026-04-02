## Pipeline Framework

**Parent doc:** [2026-04-02-b-unify-task-execution-engine.md](2026-04-02-b-unify-task-execution-engine.md)

**Goal:** Design and implement the shared `PipelineSDK` — the composable node framework that all three tabs (Architecture, Plans, Claude Chain) will use. This plan makes no changes to any existing feature. When complete, `PipelineSDK` compiles and is unit-tested but is not wired into anything.

**Prerequisites:** None. This is the first plan.

**Read for context:** Read all related documents before working on this plan: [b-unify-task-execution-engine.md](2026-04-02-b-unify-task-execution-engine.md), [d-architecture-tab-migration.md](2026-04-02-d-architecture-tab-migration.md), [e-plans-tab-migration.md](2026-04-02-e-plans-tab-migration.md), [f-claude-chain-migration.md](2026-04-02-f-claude-chain-migration.md)

**Deliverables for downstream plans:**
- `PipelineNode` protocol
- `TaskSource` protocol + `AITask<Output>`
- `AnalyzerNode<Input, Output>`
- `PRStep`, `ReviewStep`
- `MarkdownTaskSource` (implements `TaskSource`, parses `- [ ]` / `## - [ ]`)
- `Pipeline` execution engine (stop, pause, start-at-index, progress)

---

## - [x] Phase 1: Inventory Execution Path Differences

**Skills used**: `swift-architecture`, `ai-dev-tools-review`
**Principles applied**: Read all three feature use-case sets before writing the table so every behavior is represented; flagged any behavior without a clear node home with ⚠️.

**Skills to read:** `swift-architecture`, `ai-dev-tools-review`

Perform a line-by-line comparison of `RunChainTaskUseCase.swift` and `ExecutePlanUseCase.swift`. The goal is to map every behavior to a future pipeline node type so that the Phase 2 interface design covers everything.

Files compared (actual paths in repo):
- `AIDevToolsKit/Sources/Features/ClaudeChainFeature/usecases/RunChainTaskUseCase.swift`
- `AIDevToolsKit/Sources/Features/MarkdownPlannerFeature/usecases/ExecutePlanUseCase.swift`

Also audited:
- `AIDevToolsKit/Sources/Features/ArchitecturePlannerFeature/usecases/` — all 12 use cases

### Inventory Table

| Behavior | Current location | Future pipeline node | Notes/risks |
|----------|-----------------|---------------------|-------------|
| Load project config (assignees, reviewers, max PRs) | `RunChainTaskUseCase` phase 1 | `Pipeline` config struct / `ProjectConfiguration` passed in | Config loaded once before pipeline starts; not a node itself |
| Fetch + checkout base branch | `RunChainTaskUseCase` phase 1 | Implicit pipeline setup step or `Pipeline` pre-run hook | Must run before `MarkdownTaskSource` reads the spec file |
| Load spec / find plan file | `RunChainTaskUseCase` (spec), `ExecutePlanUseCase` (plan path) | `MarkdownTaskSource` init | Both use `MarkdownPipelineSource`; unified in `MarkdownTaskSource` |
| Task discovery — `.task` format, skip completed + remote-branch-exists | `RunChainTaskUseCase` | `MarkdownTaskSource.nextTask()` | Branch-existence check is Chain-specific; needs a hook or subclass |
| Task index override (start at specific task) | `RunChainTaskUseCase` `options.taskIndex` | `Pipeline.startAtIndex` | Maps cleanly to the planned `start-at-index` API |
| Phase discovery — `.phase` format | `ExecutePlanUseCase` | `MarkdownTaskSource` (`.phase` format) | Already unified via `MarkdownPipelineSource(format:)` |
| Feature branch creation | `RunChainTaskUseCase` phase 1b | `PRStep` setup / pre-AI node | Chain-specific; not in Plans or Architecture tabs |
| Pre-action script | `RunChainTaskUseCase` phase 2 | `ScriptNode` (new, not in current plan) ⚠️ | No node defined for pre/post scripts in plan deliverables |
| Post-action script | `RunChainTaskUseCase` phase 4 | `ScriptNode` (new, not in current plan) ⚠️ | Same as pre-script; could be generalized as `ShellStep` |
| AI task execution (streaming) | `RunChainTaskUseCase` phase 3, `ExecutePlanUseCase.executePhase` | `AITask` node | Both use `client.run`; Chain uses free-form, Plans uses structured |
| Structured AI execution | `ExecutePlanUseCase` (`PhaseResult`), all ArchPlanner use cases | `AnalyzerNode<Input, Output>` | Schema-driven; Architecture tab uses this exclusively |
| Cost extraction after AI run | `RunChainTaskUseCase` | `PRStep` (post-AI cost capture) | `ChainPRHelpers.extractCost()` — Chain-specific metric |
| Commit uncommitted AI changes | `RunChainTaskUseCase` phase 5 | `PRStep` or a `CommitNode` ⚠️ | Not clearly a `PRStep` concern; may need its own node |
| Mark task/phase complete in markdown | `RunChainTaskUseCase`, `ExecutePlanUseCase` | `MarkdownTaskSource.markComplete(_:)` | Already unified via `MarkdownPipelineSource.markStepCompleted` |
| Staging-only early exit | `RunChainTaskUseCase` `options.stagingOnly` | `Pipeline` config `stagingOnly: Bool` | Already planned in `Pipeline` configuration struct |
| Review pass (optional AI re-review) | `RunChainTaskUseCase` phase 5b | `ReviewStep` | Structured output (`ReviewOutput`); conditional on `review.md` existing |
| Append review note to spec | `RunChainTaskUseCase.appendReviewNote` | `ReviewStep` post-action | Inline file mutation; belongs inside `ReviewStep` |
| Branch push | `RunChainTaskUseCase` phase 5 | `PRStep` | Direct `git push --force` |
| Repo slug detection | `RunChainTaskUseCase` | `PRStep` | `ChainPRHelpers.detectRepo` — Chain-specific |
| Capacity check (max open PRs) | `RunChainTaskUseCase` | `PRStep` | Throws `capacityExceeded`; guard runs before `gh pr create` |
| PR creation (draft, label, assignees, reviewers) | `RunChainTaskUseCase` | `PRStep` | Already-exists recovery also needed |
| PR number retrieval | `RunChainTaskUseCase` | `PRStep` | `gh pr view --json number` |
| Summary generation (AI PR description) | `RunChainTaskUseCase` phase 6 | `PRStep` or a `SummaryNode` ⚠️ | Non-fatal; could be a second `AITask` chained after `PRStep` |
| PR comment posting (cost + summary report) | `RunChainTaskUseCase` phase 7 | `PRStep` | `MarkdownReportFormatter` + `gh pr comment` |
| Time-limit enforcement | `ExecutePlanUseCase` | `Pipeline` config `maxMinutes: Int?` | Already planned in `Pipeline` configuration struct |
| Uncommitted-changes detection (warning) | `ExecutePlanUseCase` | `Pipeline` pre-run check / progress event | Not a node; emitted as `.uncommittedChanges` progress event |
| `executeMode: .all \| .next` | `ExecutePlanUseCase` | `Pipeline` config `executionMode` | Already planned |
| Credential resolution (`GH_TOKEN`) | `ExecutePlanUseCase.executePhase` | `Pipeline` config / env injection | Passed as `AIClientOptions.environment`; should be in pipeline setup |
| Skills injection into prompt | `ExecutePlanUseCase.parseSkillsToRead` | `MarkdownTaskSource` or `AITask` prompt builder ⚠️ | Parsed from plan file annotations; unclear if `MarkdownTaskSource` or `AITask` owns this |
| Phase failure + log write | `ExecutePlanUseCase` | `Pipeline` error handling + `PhaseLogNode` ⚠️ | Log directory managed outside node; needs a logging hook |
| Architecture diagram stop flag | `ExecutePlanUseCase` | `Pipeline` mid-run inspection hook ⚠️ | Checks for a `-architecture.json` sidecar file; no clear node home |
| Between-phases callback | `ExecutePlanUseCase` `betweenPhases` closure | `Pipeline` inter-node hook | Already covered by `Pipeline` execution loop design |
| 2-second delay between phases | `ExecutePlanUseCase` | `Pipeline` execution loop (rate-limit policy) ⚠️ | Hardcoded sleep; should be configurable or removed |
| Move plan to `completed/` | `ExecutePlanUseCase.moveToCompleted` | `MarkdownTaskSource` post-completion action ⚠️ | Or a `Pipeline.onAllCompleted` callback |
| Plan log writing (per-phase stdout) | `ExecutePlanUseCase.writePhaseLog` | `Pipeline` logging hook / `PhaseLogNode` ⚠️ | Decoupled from execution; best as a pipeline-level observer |
| Requirements extraction (AI) | `FormRequirementsUseCase` (ArchPlanner) | `AnalyzerNode<FeatureRequest, [Requirement]>` | Structured output only; SwiftData persistence is caller concern |
| Architecture info compilation (AI) | `CompileArchitectureInfoUseCase` (ArchPlanner) | `AnalyzerNode<JobContext, ArchInfoResult>` | Reads `ARCHITECTURE.md` from repo path |
| Layer planning (AI) | `PlanAcrossLayersUseCase` (ArchPlanner) | `AnalyzerNode<ArchInfoResult, [Component]>` | References prior step summary via SwiftData |
| Conformance scoring (AI) | `ScoreConformanceUseCase` (ArchPlanner) | `AnalyzerNode<[Component], [GuidelineMapping]>` | Structured output; mid-pipeline write to SwiftData |
| Implementation decision recording (AI) | `ExecuteImplementationUseCase` (ArchPlanner) | `AnalyzerNode<PhaseComponents, PhaseResponse>` | Phase-grouped loop; each group is one AI call |
| Report generation (non-AI) | `GenerateReportUseCase` (ArchPlanner) | Non-AI terminal node ⚠️ | No `AIClient` dependency; does not fit `AnalyzerNode` pattern |
| Followups compilation (AI) | `CompileFollowupsUseCase` (ArchPlanner) | `AnalyzerNode<JobContext, [Followup]>` | Post-execution analysis step |
| SwiftData-backed inter-step state | All ArchPlanner use cases | ⚠️ No node equivalent — Architecture tab owns this | ArchPlanner passes context via `PlanningJob` in SwiftData, not through node I/O; pipeline cannot own this |

### Flagged Items Without Clear Node Home

- **`ScriptNode`** — pre/post action scripts in Chain not in any planned deliverable. Recommend adding to Phase 2 design or scoping out.
- **`CommitNode`** — committing AI-generated changes is a distinct responsibility from `PRStep`. Needs explicit placement.
- **`SummaryNode`** — AI-generated PR summary could be its own node or folded into `PRStep`; decide in Phase 2.
- **Skills injection** — `parseSkillsToRead` reads plan file annotations; unclear whether `MarkdownTaskSource` or the `AITask` prompt-builder owns this.
- **Phase log writing** — best as a pipeline-level observer pattern (similar to `onProgress`), not a node.
- **Architecture diagram stop** — mid-pipeline file-existence check; best as a `Pipeline` inspection hook or `.phase` node side effect.
- **2-second inter-phase delay** — hardcoded; should be removed or made a configurable `Pipeline` policy.
- **Move-to-completed** — could be a `MarkdownTaskSource` callback or a `Pipeline.onAllCompleted` hook.
- **SwiftData-backed state (ArchPlanner)** — the Architecture tab's inter-step context lives in `PlanningJob` / SwiftData, not in node return values; the unified pipeline cannot own this and must treat `AnalyzerNode` outputs as opaque, with the caller persisting results.

## - [ ] Phase 2: Design the Pipeline Framework

**Skills to read:** `swift-architecture`, `configuration-architecture`

Design all interfaces. No code written yet — document decisions inline in this plan before Phase 3 begins. Bill reviews and approves before implementation starts.

Decisions to make:

**`PipelineNode` protocol**
- What does every node expose? (async `run(context:)`, progress events, cancellation)
- How does a node receive inputs from prior nodes? (typed context object passed through, or explicit typed chaining?)

**`TaskSource` protocol**
- `func nextTask() -> AITask?`
- `func markComplete(_ task: AITask)`
- What does `AITask` carry? (`id`, `instructions: String`, output type token)

**`AITask<Output>` generics**
- Does the `Pipeline` need to be typed over `Output`, or does each node erase to `Any` internally?
- How does a consumer (e.g. `ClaudeChainService`) recover the typed result?

**`AnalyzerNode<Input, Output>`**
- Input: prior context or explicit typed value
- Output: typed artifact (e.g. `MarkdownPlan`, `ArchitectureDiagram`, `ConformanceReport`)
- Mid-pipeline task injection: when `AnalyzerNode` produces a `MarkdownPlan`, how does it splice a new `MarkdownTaskSource` into the running pipeline?

**`PRStep`**
- Inputs: branch name, base branch, `ProjectConfiguration`
- How does it receive the result of the preceding `AITask`? (cost metrics, git diff)

**`ReviewStep`**
- How does the pipeline pause and surface the approval gate to the Mac app?
- What does resume look like? (continuation, callback, async signal?)

**`Pipeline` configuration struct**
- `executionMode: .nextOnly | .all`
- `maxMinutes: Int?`
- `stagingOnly: Bool`
- `provider: AIProvider`

**`MarkdownTaskSource`**
- Confirm it implements `TaskSource`
- Confirm `MarkdownParser` is the only markdown-aware type — `MarkdownTaskSource` uses it; no other node knows about markdown

**Layer placement**
- Confirm `PipelineSDK` is the right target name with `swift-architecture`
- `MarkdownParser` stays in `PipelineSDK` or moves to its own target?

## - [ ] Phase 3: Implement PipelineSDK

**Skills to read:** `swift-architecture`

Implement everything designed in Phase 2. Do NOT wire into any existing feature.

Tasks:
- Create `PipelineSDK` target (or extend existing `PipelineSDK` if already present — audit first)
- Implement `PipelineNode` protocol
- Implement `TaskSource` protocol and `AITask<Output>`
- Implement `MarkdownTaskSource` — wraps `MarkdownParser`, handles `.task` (`- [ ]`) and `.phase` (`## - [ ]`) formats
- Implement `Pipeline` execution loop — drives nodes in sequence, handles stop/pause/start-at-index, emits progress events
- Implement `AITask` node execution — delegates to `AIClient` via `ProviderRegistry`
- Implement `AnalyzerNode` — structured AI output, mid-pipeline task injection mechanism
- Implement `PRStep` — PR creation, branch push, cost comment, capacity check (extracted from `RunChainTaskUseCase`)
- Implement `ReviewStep` — pause + async resume

Unit tests (cover before marking this phase complete):
- `MarkdownTaskSource`: next-task selection, all-tasks iteration, checkbox round-trip (marks correct line in file)
- `.task` and `.phase` format parsing
- `Pipeline` next-only vs. all-tasks execution modes
- `Pipeline` stop and pause/resume
- `Pipeline` start-at-index (skips earlier nodes)
- `AnalyzerNode` mid-pipeline task injection
- `PRStep` capacity check enforcement
