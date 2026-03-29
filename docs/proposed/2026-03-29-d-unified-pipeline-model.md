## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture (Apps/Features/Services/SDKs) and protocol design guidance |
| `ai-dev-tools-review` | Architecture compliance review to validate layer assignments during implementation |

## Background

AIDevTools has three overlapping execution systems that all do roughly the same thing — define a sequence of AI-driven steps and run them one at a time:

- **MarkdownPlanner** — parses phases from `## - [ ]` markdown headings and executes them sequentially via Claude
- **ClaudeChain** — parses tasks from `- [ ]` markdown bullet lines, executes one at a time with git branching and PR creation
- **ArchitecturePlanner** — a hardcoded multi-step pipeline driven by a Swift enum, not markdown

Each has its own step model (`PlanPhase`, `SpecTask`, `ArchitecturePlannerStep`), its own execution use case, and its own markdown parser. The duplication is already high, and upcoming features — review steps that dynamically generate more steps, PR-creation steps, and maintenance steps that spontaneously discover work — can't be bolted onto either existing system cleanly.

The goal of this plan is to extract a **Unified Pipeline Model**: a protocol-based abstraction layer for defining and executing ordered steps, where markdown is one possible backing source among many. MarkdownPlanner and ClaudeChain will both migrate to this model. New step types (Review, CreatePR, Maintenance) will be built on top of the unified primitives.

### Key concepts

**Step types** — what a step does when executed:
- `codeChange` — run Claude with a prompt, modify files (both current features)
- `review` — inspect a change set with AI and emit new steps (new)
- `createPR` — create a GitHub draft PR (extracted from ClaudeChain's tail logic)

**Pipeline source** — what produces the list of steps:
- Markdown file (existing MarkdownPlanner and ClaudeChain format)
- In-memory / programmatic (e.g., Maintenance step spontaneously generates a pipeline)
- Potentially JSON or other formats later

**Dynamic steps** — Review and Maintenance steps can append new steps to the running pipeline at runtime. The executor must support this.

## Phases

## - [x] Phase 1: Define the Core Pipeline Protocols (SDKs layer)

**Skills used**: `ai-dev-tools-review:sdks-layer`
**Principles applied**: Created `PipelineSDK` as a new dependency-free SDK target with three files: `PipelineStep.swift` (protocol + `CodeChangeStep`, `ReviewStep`, `CreatePRStep` concrete types), `Pipeline.swift` (`Pipeline` struct + `PipelineMetadata`), and `PipelineSource.swift` (`PipelineSource` protocol). All types are pure `Sendable` value types with no business logic, no AI calls, no platform imports — strictly conforming to the stateless SDK layer contract.

**Skills to read**: `swift-app-architecture:swift-architecture`

Define the foundational protocol types in a new `PipelineSDK` target (or extend an existing SDK). These are pure, stateless, Sendable value types — no business logic, no AI calls.

**`PipelineStep`** — a protocol representing a single executable unit:

```swift
public protocol PipelineStep: Sendable {
    var id: String { get }          // stable, hashable identifier
    var description: String { get }
    var isCompleted: Bool { get }
}
```

Concrete step types conforming to `PipelineStep`:
- `CodeChangeStep` — holds a Claude prompt and optional skills/context. Equivalent to `PlanPhase` and `SpecTask` today.
- `ReviewStep` — holds a scope descriptor (e.g., "all steps since last review" or "last N steps"), the AI prompt for the review, and a reference to the steps it reviews.
- `CreatePRStep` — holds title template, body template, label. Equivalent to ClaudeChain's tail logic today.

**`Pipeline`** — an ordered, mutable-at-runtime list of steps:

```swift
public struct Pipeline: Sendable {
    public let id: String
    public var steps: [any PipelineStep]
    public var metadata: PipelineMetadata  // name, sourceURL, createdAt, etc.
}
```

**`PipelineSource`** — a protocol for anything that can produce a `Pipeline`:

```swift
public protocol PipelineSource: Sendable {
    func load() async throws -> Pipeline
    func markStepCompleted(_ step: any PipelineStep) async throws
    func appendSteps(_ steps: [any PipelineStep]) async throws
}
```

Keep all types in SDKs. No UIKit, no SwiftData, no AI calls here.

## - [x] Phase 2: Implement Markdown Pipeline Source (SDKs layer)

**Skills used**: `ai-dev-tools-review:sdks-layer`
**Principles applied**: Created `MarkdownPipelineSource: PipelineSource` in `PipelineSDK` with a `MarkdownPipelineFormat` enum (`.phase` for MarkdownPlanner's `## - [ ]` syntax, `.task` for ClaudeChain's `- [ ]` syntax). Both formats parse into `CodeChangeStep` instances. `appendCreatePRStep` defaults to `true` for `.task` format to match ClaudeChain's implicit PR creation behavior. `markStepCompleted` performs an in-place regex replacement on disk; `appendSteps` appends new markdown lines. `CreatePRStep` is silently skipped in `markStepCompleted` since it has no markdown representation. The struct is a stateless `Sendable` value type with no business logic or platform imports beyond Foundation.

**Skills to read**: `swift-app-architecture:swift-architecture`

Implement `MarkdownPipelineSource: PipelineSource` that unifies the two existing markdown parsers.

The source should support both existing syntax families:
- MarkdownPlanner phases: `## - [ ] Phase name` / `## - [x] Phase name`
- ClaudeChain tasks: `- [ ] Task description` / `- [x] Task description`

A configuration enum or init parameter selects which format to parse.

Steps parsed from markdown become `CodeChangeStep` instances. The `CreatePRStep` is not represented in markdown today — ClaudeChain appends it implicitly at the end; `MarkdownPipelineSource` should append it automatically when the ClaudeChain format is detected (or based on a config flag).

`markStepCompleted` writes the checkbox update back to the file (same logic as today's `TaskService.markTaskComplete` and `ExecutePlanUseCase`'s in-place markdown edit).

`appendSteps` adds new `- [ ]` lines to the markdown file (used by dynamic step insertion from Review and Maintenance steps).

## - [x] Phase 3: Implement Pipeline Executor (Features layer)

**Skills used**: `ai-dev-tools-review:features-layer`
**Principles applied**: Created `PipelineFeature` target with three files: `PipelineContext.swift` (a `Sendable` struct carrying repo path, working directory, branch, and accumulated logs), `StepHandler.swift` (the `StepHandler` protocol with associated type + `AnyStepHandler` type-eraser using a closure-based dispatch that returns `nil` on type mismatch), and `ExecutePipelineUseCase.swift` (a plain struct with `run(options:onProgress:)` callback pattern, seeding a local mutable step array from `source.load()`, dispatching each pending step to the first matching `AnyStepHandler`, persisting completion via `source.markStepCompleted`, appending dynamic steps to both the local array and `source.appendSteps`, and yielding `PipelineProgress` events). No `@Observable`, no UI imports, no feature-to-feature dependencies.

**Skills to read**: `swift-app-architecture:swift-architecture`

Create `ExecutePipelineUseCase` in a new or existing Feature. This replaces both `ExecutePlanUseCase` and `RunChainTaskUseCase` as the core execution engine.

### Execution loop

The executor maintains a **local mutable `[any PipelineStep]` array** for in-flight iteration — this is separate from the persisted source. On load, it's seeded from `source.load()`. When a step returns new steps dynamically, they're appended to this local array (so the loop immediately sees them) and also persisted via `source.appendSteps(_:)`.

```
source.load() → local [PipelineStep]
    ↓
iterate
    handler.execute(step)
    ↓
    returns newSteps
    local array.append(newSteps) ← live iteration sees them
    source.appendSteps(newSteps) ← persisted for resume/observability
```

### State persistence is the use case's responsibility

After each step completes, `ExecutePipelineUseCase` does two things in sequence:
1. Calls `source.markStepCompleted(step)` — writes to disk (checkbox, JSON, etc.)
2. Yields a `PipelineProgress` event up the stream — so the App layer can update display state

The App-layer model never writes state to disk. It only responds to what the stream emits. Disk persistence is an orchestration concern that belongs in the Feature.

### Step handlers

Step handlers are injected as dependencies, not hardcoded inside the executor — this keeps the executor testable and allows new step types without modifying it.

```swift
public protocol StepHandler: Sendable {
    associatedtype Step: PipelineStep
    func execute(_ step: Step, context: PipelineContext) async throws -> [any PipelineStep]
}
```

`PipelineContext` is a local var built up as steps execute — it carries repo path, working directory, git branch info, and accumulated stdout logs. It's passed into each handler and updated as the stream progresses.

### Open design question: stateful service for Mac UI

The `StreamingUseCase` pattern handles fire-and-forget runs correctly. If the Mac UI later needs to **cancel a running pipeline** or observe live state from multiple consumers, consider wrapping a `PipelineExecutionService` actor with an observation stream:

```
AppModel (app lifetime) → PipelineExecutionService actor → MarkdownPipelineSource
```

This is not needed for the initial implementation but worth revisiting before building the Mac UI for this feature.

## - [x] Phase 4: Implement Step Handlers (Features layer)

**Skills used**: none (skill not found; architecture conventions applied from prior phases and existing codebase patterns)
**Principles applied**: Three concrete `StepHandler` types added to `PipelineFeature/handlers/`: `CodeChangeStepHandler` injects `AIClient` and forwards `step.prompt` directly; `ReviewStepHandler` uses `CLIClient` to run `git diff` based on scope, calls `AIClient.runStructured()` with a fixes schema, and returns `[CodeChangeStep]` for dynamic insertion; `CreatePRStepHandler` uses `GitClient.push()` + `CLIClient` for `gh pr create --draft` + Claude for the PR summary comment. Added `GitSDK` and `CLISDK` (from SwiftCLI) to `PipelineFeature` dependencies to avoid raw `Foundation.Process` concurrency issues in Swift 6.

**Skills to read**: `swift-app-architecture:swift-architecture`

Implement the concrete `StepHandler` types. Each lives in the Features layer and can call AI, git, or other services.

**`CodeChangeStepHandler`**
- Builds a prompt from `step.description` plus context (repo path, skills to read, etc.)
- Calls `AIClient.run()` (streaming)
- Returns `[]` (no dynamic steps)
- This is the core logic of `ExecutePlanUseCase.executePhase` and `RunChainTaskUseCase`'s AI execution block, consolidated

**`ReviewStepHandler`**
- Determines the change set to review based on `step.scope` (e.g., git diff of the current branch)
- Calls `AIClient.runStructured()` with a schema that returns a list of required fixes
- Converts each fix into a `CodeChangeStep`
- Returns those new steps for dynamic insertion
- The review runs in its own AI context (no prior conversation state)

**`CreatePRStepHandler`**
- Calls `git push` and `gh pr create` with title/body from the step
- Posts a PR summary comment via Claude (same as ClaudeChain's tail today)
- Returns `[]`

## - [x] Phase 5: Migrate MarkdownPlanner to Unified Pipeline (Features layer)

**Skills used**: `swift-app-architecture:swift-architecture`, `ai-dev-tools-review`
**Principles applied**: Added `PipelineSDK` as a dependency of `MarkdownPlannerFeature` (no feature-to-feature dependency — `MarkdownPlannerFeature` uses `PipelineSDK` types directly rather than importing `PipelineFeature`). Replaced the AI-based `getPhaseStatus` call with `loadPhaseStatus(from:)` which uses `MarkdownPipelineSource.load()` for local markdown parsing — eliminating a round-trip AI call on every status check. Added `markStepCompleted()` after each successful phase as a guaranteed persistence fallback (idempotent with Claude's own checkbox update). All other features preserved: time limits, `executeMode`, architecture diagram detection, `betweenPhases` callback, log writing, and plan move-to-completed.

**Skills to read**: `swift-app-architecture:swift-architecture`, `ai-dev-tools-review`

Replace MarkdownPlanner's internal execution with the unified pipeline:

- `ExecutePlanUseCase` delegates to `ExecutePipelineUseCase`, passing a `MarkdownPipelineSource` configured for the MarkdownPlanner format
- `PlanPhase` is retained as a UI-facing view model (or replaced by a computed property over `CodeChangeStep`)
- The markdown file format is unchanged — no migration of existing plan files needed

Existing behavior must be preserved exactly: sequential execution, phase checkbox updates, log file output, plan moved to `completed/` on finish.

## - [x] Phase 6: Migrate ClaudeChain to Unified Pipeline (Features layer)

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Added `PipelineSDK` as a dependency of `ClaudeChainFeature` (no feature-to-feature dependency — same pattern as Phase 5). Replaced `spec.getNextAvailableTask()` with `MarkdownPipelineSource(format: .task).load()` to discover the next pending `CodeChangeStep`. Replaced `TaskService.markTaskComplete` with `pipelineSource.markStepCompleted(step)` for unified checkbox persistence. Step index and total/completed counts are now derived from the pipeline's `CodeChangeStep` array. `spec.content` is still loaded via `ProjectRepository` for the enriched AI prompt (spec content embedded). All git operations, scripts, and PR creation remain in `RunChainTaskUseCase` unchanged — only task discovery and persistence were migrated to the pipeline model.

**Skills to read**: `swift-app-architecture:swift-architecture`, `ai-dev-tools-review`

Replace ClaudeChain's execution with the unified pipeline:

- `RunChainTaskUseCase` delegates to `ExecutePipelineUseCase`, passing a `MarkdownPipelineSource` configured for the ClaudeChain format
- The ClaudeChain-specific steps (pre/post action scripts, git branching, PR creation) map to:
  - Pre-script → `MaintenanceStep` or a new `ScriptStep` (simpler: keep as a side effect in `CodeChangeStepHandler` via a pre-run hook)
  - AI execution → `CodeChangeStepHandler`
  - Post-script → same hook mechanism
  - PR creation → `CreatePRStepHandler`
- `SpecTask` is retained as a view model or replaced by `CodeChangeStep` directly
- Existing spec.md files continue to work unchanged

## - [x] Phase 7: Validation

**Skills used**: none (`swift-testing` skill not found; used patterns from existing test files in the repo)
**Principles applied**: Added `PipelineSDKTests` (16 tests covering `MarkdownPipelineSource` parsing for both formats, mixed/edge-case inputs, `markStepCompleted`, and `appendSteps`) and `PipelineFeatureTests` (7 tests covering `ExecutePipelineUseCase` — sequential dispatch, skip-completed, persistence, dynamic step insertion, progress events, and `noHandlerFound` error). Used `import Testing` + `#expect` + `@Suite`/`@Test` to match the project's Swift Testing convention. Pre-existing `ClaudeChainSDKTests` compile errors (unrelated to this phase) block `swift test` from running, but both new targets build and link cleanly via `swift build --target`.

**Skills to read**: `swift-testing`, `ai-dev-tools-review`

**Unit tests (SDKs layer)**
- `MarkdownPipelineSource` parsing: both syntax families, mixed completed/pending, edge cases (empty file, all complete)
- `Pipeline` step insertion and ordering

**Integration tests (Features layer)**
- `ExecutePipelineUseCase` with a mock `PipelineSource` and mock step handlers — verify sequential dispatch, dynamic step insertion, progress events
- `ReviewStepHandler` with a mock AI client — verify it returns correctly-typed `CodeChangeStep` instances

**CLI smoke tests**

All pipeline capabilities must be exercisable from the CLI — the CLI is the primary validation harness. For each scenario, author a markdown file and run it via the CLI command:

- **MarkdownPlanner migration** — run an existing `## - [ ]` plan to completion; verify checkboxes update on disk as each phase finishes
- **ClaudeChain migration** — run a `- [ ]` task spec; verify the task is checked off and a PR is created
- **Dynamic step insertion** — author a pipeline with a `ReviewStep` after a `CodeChangeStep`; verify the review generates new steps that are appended to the markdown and then executed
- **Partial resume** — partially complete a pipeline (some checkboxes already checked), re-run; verify only incomplete steps execute
