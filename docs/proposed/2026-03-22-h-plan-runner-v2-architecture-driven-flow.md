## Implementation Phases

- [ ] Phase 1: SwiftData models in ArchitecturePlannerService (Request, Requirement, Guideline, GuidelineCategory, ImplementationComponent, ConformanceScore, PlanningJob, ProcessStep, UnclearFlag, FollowupItem)
- [ ] Phase 2: Use cases in ArchitecturePlannerFeature (FormRequirements, CompileArchitectureInfo, PlanAcrossLayers, BuildImplementationModel, ScoreConformance, ExecuteImplementation, GenerateReport, ManageGuidelines)
- [ ] Phase 3: CLI subcommands (arch-planner group: create, inspect, update, score, execute, report, guidelines)
- [ ] Phase 4: Mac app model and views (ArchitecturePlannerModel, step-based navigation UI, graphical layer view, guideline browser, approve/revise loops)
- [ ] Phase 5: Wire everything together, ensure swift build passes
- [ ] Phase 6: Unit tests for models, use cases, and services
- [ ] Phase 7: Validation — end-to-end manual test, PR creation

---

## Background

The current planning feature follows a straightforward generate → execute → complete flow. Plans are generated as markdown with numbered phases, executed sequentially by Claude, and moved to a completed directory. While functional, the process lacks structured architectural reasoning — it doesn't formally gather requirements, consult architecture rules, determine where logic belongs across layers, or provide traceability from requirements through to implementation decisions.

This will be a **new, separate feature** in the app — not a modification of the existing plan runner. The existing feature remains as-is and the two will live side by side. The new feature is inspired by the existing one but takes a fundamentally different, model-driven approach.

The feature needs a **polished Mac app UI** for visualizing and interacting with the models, maps, and scoring. All capabilities available in the Mac app must also be available via the **CLI** — the CLI is not a reduced subset, it's full-parity.

The new flow introduces an **architecture-driven planning process** that treats requirements gathering, layer placement, and rule compliance as first-class steps. The result is a plan that is not just a task list, but a traceable map from user intent → requirements → architectural decisions → implementation → validation.

## Core Concept: Model-Driven Process

The entire process is backed by **structured models** (SwiftData) at every stage — not just prose markdown. Each step produces or updates a model:

- **Request model** — the user's description in text, updated as iterations occur
- **Requirements model** — discrete requirements extracted from the request
- **Guidelines model** — architectural guidelines applicable to the project (see Guidelines section below). This is **static, shared across planning jobs** — it represents the repo's standards, not a single plan's state
- **Implementation model** — discrete changes, file impacts, references to applicable guidelines (e.g. by file path), and derived conformance scores. This is **per planning job** — it captures everything from the time a plan starts through completion

These models evolve as the process progresses — the implementation model changes as code iterations occur, conformance scores update after evaluation passes, etc. The models are the source from which all user-facing visualizations (maps, summaries, reports) are derived.

### Guidelines

Guidelines are the rules and standards that govern how code should be written and where it should live. Rather than nesting guidelines into a hierarchy, guidelines are organized by **user-defined categories** (e.g. architecture, conventions, swiftui, testing, etc.). A guideline belongs to one or more categories, and categories make it easy to filter and browse.

Each guideline defines:
1. **What it applies to** — matching criteria that determine when the guideline is relevant:
   - **File path globs** — match by file path, directory, or pattern (e.g. `Sources/Features/**/*.swift`, `**/Views/*.swift`)
   - **Description-based** — match by what the code is doing conceptually (e.g. "creating an observable model", "adding a CLI command")
   - The AI determines which guidelines apply to a given implementation component and stores the mapping in the model
2. **Examples of good vs bad** — concrete code showing correct and incorrect approaches

The `swift-architecture` and `swift-swiftui` skills will be transformed into guidelines and stored as part of the model. This is the seed data.

Guidelines are **per-repo**. The guideline source path can be a relative path within the repo, an absolute path, or a `~/` home-relative path. Guidelines are **editable through the app UI** (not just as files) and via CLI.

**In the app**, guidelines should be browsable during review:
- Show which guidelines apply to each implementation component, and **why** they matched
- Show guidelines that do **not** apply (so the user can verify nothing was missed)
- This mapping from guidelines → implementation details is critical to ensuring the implementation meets standards

### Model Storage

Models are persisted using **SwiftData** rather than JSON files. This makes the Mac app more reactive and simplifies querying/updating models. The SwiftData store is per-repo at `~/.ai-dev-tools/{repo-name}/architecture-planner/`. No CloudKit sync.

### Model API

The models need an API so the AI can read and mutate them during the process. This will be implemented as **new commands on the existing Swift CLI** in this project. The AI calls CLI commands to create, update, query, and score models at each step. The user can also use these same CLI commands to revise, rerun steps, and interact with the approve-or-revise loops — full parity with the Mac app UI.

## New Flow (Skeleton)

### 1. User Describes the Feature
- Natural language input (same as today)

### 2. Requirements Formation
- Extract discrete requirements from the user's description
- **No interactive Q&A for now** — the AI takes the user's input as-is and forms requirements from it (interactive clarification is a future enhancement)
- Requirements are written to the model for user review; the user can approve or request revision
- Revision uses the same text input as the initial prompt — the loop continues until the user confirms the requirements are good enough
- Output: a **requirements model** (SwiftData) with an entry per requirement

### 3. Architectural Information Compilation
- Identify the levels/layers of the application
- Load a **high-level overview** of project guidelines first — this overview is a derivative of more detailed guidelines
- Use the high-level overview for initial planning before digging into detailed guidelines
- All guidelines live **in this repo** as the single source of truth — not loaded from external skills at runtime
- Content from the `swift-architecture` and `swift-swiftui` skills will be **transformed into guidelines** and stored in the model as seed data
- This keeps guidelines easy to iterate on without worrying about stale or out-of-sync skill content
- Early versions of this feature will not use the existing skill system for guideline lookup

### 4. Plan Implementation Across Layers
- Determine where in the existing codebase the feature touches or integrates (intercept points)
- Decide where each piece of logic belongs based on architectural rules and practical concerns
- Per-layer implementation plan following the rules identified in step 3

### 5. Checklist Validation
- Use a checklist to validate and iterate on the placement/design decisions before implementing

### 6. Implementation Model Formation
- Build a structured **implementation model** (SwiftData) where each entry describes a small, discrete change:
  - Files affected or new files to create
  - Applicable guidelines for that change, with reasoning for why each matched
  - Tradeoffs/considerations made when evaluating how those guidelines apply
  - Conformance score (1–10) per guideline
- Each requirement from the requirements model (step 2) maps to **one or more** implementation components
- A mapping links implementation components back to their originating requirements
- **Visual Map** showing layers mapping to requirements and guidelines

### 7. User Review of Implementation Plan
- User reviews the implementation model, guideline mappings, and conformance scores
- Same approve-or-revise loop as step 2 (reusable UI) — user can request updates via text input until satisfied

### 8. Complete Implementation
- Execute the plan phase-by-phase
- **Context mode option**: the user can choose whether to reuse a single AI session (Claude thread) across multiple steps or give each step its own session. A combined session is faster and avoids reloading context; separate sessions provide isolation
- **After each phase**, before moving to the next:
  - Evaluate what was just implemented against the applicable guidelines
  - Check for **newly relevant guidelines** (from the full guideline set) that weren't originally matched — apply if appropriate
  - Do an improvement pass if the evaluation warrants it
  - For every decision (change made or change deliberately skipped), record in the model: what guideline triggered it, what was decided, and the rationale
- These per-phase decision records are stored in the model so they can be **reviewed retrospectively** — showing which choices were made, why, and which guidelines drove them

### 9. Final Report & Review
- Same reusable UI as steps 2 and 7 — user can review and iterate
- Shows all collected details: requirements, guideline mappings, conformance scores, per-phase decisions and rationale
- Updated visual map reflecting actual outcomes
- User can drill into any layer or component to see what happened and why

### 10. User Iteration
- The UI presents a **list of all steps** in the process that the user can click through to inspect and adjust
- The user can **go back** to any previous step and rerun it
- When a prior step is rerun, all subsequent steps are marked with a **stale indicator** so the user knows those outputs may no longer reflect the current state
- The user can then rerun stale steps forward to bring everything back in sync

### 11. Followups Compiled
- Deferred work, open questions, and future improvements are tracked as part of the plan model itself (not a separate artifact)

---

## Unclear Guideline Flagging

Throughout evaluation and implementation, the AI may encounter guidelines that are **ambiguous, contradictory, or insufficient** to make a confident decision. When this happens:
- The decision is flagged with an **unclear indicator** in the model
- The flag includes: which guideline was unclear, what the ambiguity was, and what choice was made despite it
- These flags surface in the UI so the user can see where the AI had to make a judgment call with incomplete guidance
- The user can use these flags to **improve guidelines for future use** — clarifying wording, adding examples, or resolving contradictions
- Flags are visual indicators only by default, but the user can **promote a flag to a followup item** in the plan model

---

## Graphical Layer View

Throughout multiple steps (6, 7, 8, 9), the user should see an **interactive graphical view of the architectural layers** they can click on to drill into where things go. This borrows from the layer visualization already implemented in the existing app (see existing implementation for inspiration) but should be updated/improved for this feature's design. This view is reused wherever layer context is relevant — it is not a one-off.

## Verification

### Unit Tests
- Standard unit tests for models, use cases, and services

### End-to-End Integration Test
- Drive the **entire feature end-to-end from the UI** using a real AI (Claude)
- The app has access to Claude via an **environment variable** — the test should use this to perform the full flow: describe feature → form requirements → compile guidelines → plan → review → implement → evaluate → report
- The test runs against **this repo (AIDevTools)** as the target project
- **Success criteria**: a text report covering every step in the flow, validating that each step's requirements were met
- This report should be **included in the PR** so the reviewer can confirm the full flow was exercised

---

## Implementation Guidance (Building This Feature)

This feature follows the same layered architecture as the rest of the app. Below is guidance on where each component lives.

### Layer Map

| Layer | New Target(s) | Responsibility |
|-------|---------------|----------------|
| **SDKs** | (none expected initially — reuse existing `ClaudeCLISDK`, `RepositorySDK`, `GitSDK`) | Domain utilities |
| **Services** | `ArchitecturePlannerService` | SwiftData models (Request, Requirement, Guideline, ImplementationComponent, Score), persistence, settings |
| **Features** | `ArchitecturePlannerFeature` | Use cases that orchestrate each flow step — e.g. `FormRequirementsUseCase`, `CompileArchitectureInfoUseCase`, `PlanAcrossLayersUseCase`, `ScoreConformanceUseCase`, `EvaluateAgainstPlanUseCase` |
| **Apps / CLI** | New subcommand group (e.g. `arch-planner`) on existing CLI | Full-parity CLI commands for every operation — create, inspect, update, score, execute, report |
| **Apps / Mac** | `ArchitecturePlannerModel` + views | @Observable @MainActor model, SwiftUI views for model visualization, scoring maps, iteration UI |

### Conventions to Follow

- **One use case per file** — each step in the flow maps to a use case struct with `Options`, `Result`, and `Progress` types
- **Service layer has no dependencies** — pure Codable models and file persistence only
- **Feature layer depends on Services + SDKs** — never on Apps
- **CLI and Mac app both depend on Feature + Service layers** — neither contains business logic
- **Alphabetical ordering** in Package.swift targets, enum cases, imports
- **CLI commands use ArgumentParser** (`AsyncParsableCommand`) with hierarchical subcommands
- **Mac models are `@Observable` `@MainActor`** with state enums and injected use case dependencies

### Architecture Rule Docs

The `swift-architecture` and `swift-swiftui` skills (external) will be **copied into this repo** as reference docs for the feature to consult. These are the seed data for the rules model — the feature's own planning process will use them as source of truth for layer placement and SwiftUI patterns.
