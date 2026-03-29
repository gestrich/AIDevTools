> **2026-03-29 Obsolescence Evaluation:** Plan reviewed, still relevant. This comparison document clarifies the distinct purposes of Architecture Planner (analysis & scoring) vs Plans (code generation & execution). Useful documentation for understanding feature boundaries and use cases.

# Architecture Planner vs Plans: Feature Evaluation

## Overview

AIDevTools has two features that involve planning work before implementation: **Architecture Planner** and **Plans** (Plan Runner). Despite both involving "planning," they serve fundamentally different purposes and operate at different levels of abstraction.

## Architecture Planner

### Purpose
An AI-powered **architectural analysis pipeline** that evaluates a feature description against the codebase's architectural guidelines and produces a conformance-scored report. It answers: *"How should this feature be built to conform to our architecture?"*

### What It Does
Runs a 10-step pipeline:
1. User describes a feature in plain English
2. Claude extracts discrete requirements
3. Loads ARCHITECTURE.md and seeds architectural guidelines (14 bundled + custom)
4. Decomposes requirements into implementation components mapped to architectural layers
5. Validates all requirements are covered
6. Scores each component against guidelines (1-10 conformance score)
7. Simulates execution decisions against architectural principles
8. Generates a markdown report with scores, rationale, and ambiguities
9. Compiles followup items from flagged ambiguities

### Key Characteristics
- **Analysis-oriented**: Produces a report, does not write code
- **Model-rich**: 11 SwiftData models (PlanningJob, Requirement, ImplementationComponent, GuidelineMapping, ConformanceScore, PhaseDecision, UnclearFlag, FollowupItem, etc.)
- **Guideline-driven**: Central concept is scoring against architectural rules
- **Persisted in SQLite**: `~/.ai-dev-tools/{repo}/architecture-planner/store.sqlite`
- **Output**: Markdown report with conformance scores and followup items
- **No code changes**: Purely advisory

### CLI
```
arch-planner create "feature description"
arch-planner update --job <id> --step <step>
arch-planner inspect [--job <id>]
arch-planner report --job <id>
arch-planner guidelines {list|add|delete|seed}
```

---

## Plans (Plan Runner)

### Purpose
A **task automation system** that generates a phased implementation plan and then executes it, making actual code changes. It answers: *"Build this feature for me, step by step."*

### What It Does
1. User describes what to build in natural language
2. Claude matches the request to a configured repository
3. Generates a markdown plan with 3 base phases + dynamically generated implementation phases
4. Executes phases sequentially: Claude writes code, runs builds, commits changes
5. Optionally generates an architecture diagram (JSON) mapping changes to layers
6. Moves completed plans from `docs/proposed/` to `docs/completed/`

### Key Characteristics
- **Action-oriented**: Actually writes code, runs builds, creates commits and PRs
- **Model-light**: Uses markdown files with checkbox phases, minimal domain models
- **Execution-driven**: Central concept is phased code generation with build verification
- **Persisted as markdown**: `docs/proposed/{plan}.md` and `docs/completed/{plan}.md`
- **Output**: Working code changes, commits, and optionally a draft PR
- **Makes code changes**: The primary purpose

### CLI
```
plan-runner plan "what to build"
plan-runner execute [--plan <path>] [--maxMinutes 90]
plan-runner delete [--plan <path>]
```

---

## Side-by-Side Comparison

| Dimension | Architecture Planner | Plans (Plan Runner) |
|-----------|---------------------|---------------------|
| **Primary goal** | Architectural analysis & scoring | Code generation & execution |
| **Output type** | Report (markdown) | Code changes + commits |
| **Writes code?** | No | Yes |
| **AI usage** | Structured analysis (extract, score, evaluate) | Code generation & build verification |
| **Storage** | SQLite (SwiftData) | Markdown files in repo |
| **Data model complexity** | High (11 models, relationships, scores) | Low (markdown with checkboxes) |
| **Guideline system** | Core feature (14 bundled + custom) | None |
| **Conformance scoring** | Yes (1-10 per component) | No |
| **Phase execution** | Analysis steps (no side effects) | Code-writing steps (commits, builds) |
| **Architecture awareness** | Deep (reads ARCHITECTURE.md, seeds guidelines) | Light (reads ARCHITECTURE.md for diagram only) |
| **Time limit** | None | Configurable (default 90 min) |
| **Repository matching** | Manual (user selects) | AI-assisted (Claude matches from prompt) |
| **Resumability** | Per-step (any step can be re-run) | Per-phase (resumes from next unchecked) |
| **End state** | Report + followup items | Completed code + optional PR |

## Where They Overlap

1. **Both take a natural language feature description** as input
2. **Both involve Claude analyzing what needs to be built** (requirements extraction vs plan generation)
3. **Both have a concept of sequential phases/steps** that execute in order
4. **Both can read ARCHITECTURE.md** for architectural context
5. **Both exist in CLI and Mac app** with shared use case layers
6. **Both track progress** (step status vs phase checkboxes)

## Where They Diverge

1. **Depth vs breadth**: Architecture Planner goes deep on *how* something should be built architecturally. Plans goes broad on *actually building* it end-to-end.
2. **Advisory vs actionable**: Architecture Planner's output requires a human (or another tool) to act on it. Plans' output is the implementation itself.
3. **Guidelines are central vs absent**: Architecture Planner's entire value proposition is guideline conformance scoring. Plans has no guideline concept at all.
4. **Data richness**: Architecture Planner maintains a rich relational model of requirements, components, guidelines, scores, and followups. Plans uses flat markdown with checkboxes.
5. **Lifecycle**: Architecture Planner jobs live in SQLite indefinitely. Plans move from proposed to completed directories as markdown files.

## Observations

- The two features occupy complementary positions: Architecture Planner is the "think" phase, Plans is the "do" phase.
- Currently there is no integration between them. A natural workflow would be: run Architecture Planner to get a scored plan, then feed that into Plan Runner for execution. This doesn't exist today.
- Plans' Phase 2 ("Gather Architectural Guidance") and Phase 3 ("Plan the Implementation") loosely replicate what Architecture Planner does in a more rigorous, scored way across its 10 steps.
- Architecture Planner's "Execute Implementation" step (step 7) is misleadingly named: it simulates execution decisions but doesn't write code. Plans actually executes.
- The guideline system in Architecture Planner could add significant value to Plans if integrated, ensuring generated code conforms to architectural rules.
- Plans' architecture diagram generation (mapping file changes to layers) is a lightweight version of what Architecture Planner does with ImplementationComponent layer mapping.
