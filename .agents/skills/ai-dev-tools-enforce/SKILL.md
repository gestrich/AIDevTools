---
name: ai-dev-tools-enforce
description: >
  Orchestrates enforcement of this project's coding standards against recently changed Swift
  code. Runs in two modes: Fix mode makes direct code changes (default); Analyze mode
  produces a violation report with severity, explanation, and fix suggestions without touching
  code. Trigger Fix mode when asked to "enforce architecture", "apply reviews", "refactor to
  spec", "fix violations", or "clean up recent changes". Trigger Analyze mode when asked to
  "analyze", "review for violations", "what would you change", or "show me what's wrong".
user-invocable: true
---

# Enforce — Orchestrator

Two modes:

- **Fix** (default) — read changed files, apply all practice skills, make direct code changes. No reports, just fixes.
- **Analyze** — read changed files, apply all practice skills, produce a violation report. No code changes.

If the user's request is ambiguous, default to **Fix**.

---

## Step 1: Load the Practice Skills

Read all five practice skills before touching any code. They define every rule you will enforce:

- **Architecture**: `.agents/skills/ai-dev-tools-architecture/SKILL.md`
- **Build Quality**: `.agents/skills/ai-dev-tools-build-quality/SKILL.md`
- **Code Organization**: `.agents/skills/ai-dev-tools-code-organization/SKILL.md`
- **Code Quality**: `.agents/skills/ai-dev-tools-code-quality/SKILL.md`
- **Swift Testing**: `.agents/skills/ai-dev-tools-swift-testing/SKILL.md`

## Step 2: Get the Changed Files

```bash
git diff --name-only
```

If empty, fall back to the last commit:

```bash
git diff HEAD~1 HEAD --name-only
```

Focus only on `.swift` files. Read each changed file in full before proceeding.

## Step 3: Determine Layer

For each changed file, determine its layer before applying rules:

| Signal | Layer |
|--------|-------|
| `@Observable`, `@MainActor`, SwiftUI views, `AsyncParsableCommand` | **Apps** |
| `UseCase` / `StreamingUseCase` conformance | **Features** |
| Shared models/config across features, `Services/` in path | **Services** |
| Stateless `Sendable` structs, single-operation, `SDK` in module name | **SDKs** |

## Step 4: Apply Rules

Use this severity scale across both modes:

| Score | Meaning | Examples |
|-------|---------|---------|
| 9–10 | Architectural boundary violation — code in the wrong layer, upward dependencies | Feature importing App module; SDK with business logic |
| 7–8 | Structural violation — right layer, wrong principle | `@Observable` in a Feature; model orchestrating instead of calling a use case |
| 5–6 | Design friction — works but creates maintenance burden | Feature-to-feature dependency; error swallowing; scattered state booleans |
| 3–4 | Style/convention issue | Wrong file order; missing `private(set)`; AI-changelog comments |
| 1–2 | Minor nit | Naming doesn't follow `<Name><Layer>` convention |

### Fix mode

A file with many violations doesn't need a ground-up rewrite — focus on the most egregious issues and make bounded, incremental changes. A minor fix that addresses a major violation is more valuable than a perfect refactor that never ships.

Fix in this order:

**Severity 7–10 (always fix):**
- Upward dependencies, feature-to-feature imports, `@Observable` outside Apps
- SDK accepting app-specific types, SDK holding mutable state
- Code in wrong layer, model orchestrating multiple service/SDK calls

**Severity 5–6 (always fix):**
- Independent state booleans/data outside the `State` enum
- Error swallowing — propagate or set error state (see architecture skill for logging rules)
- Force unwraps, fallback values hiding failures
- Raw `String`/`[String:Any]` where typed models should exist
- Compiler warnings

**Severity 3–4 (fix if safe and bounded):**
- `private(set)` missing on state properties
- `var` properties never mutated after init → `let`
- Inline use case construction → inject via init
- Multiple types in one file, supporting types above primary type
- Debug prints, TODO/FIXME, commented-out code, AI-changelog comments
- XCTest assertions in new test files → Swift Testing

When a fix requires a new file (e.g., a use case that doesn't exist), create it in the correct layer directory — just enough to compile and preserve behavior.

When unsure if a refactor would break behavior, read call sites first. If the change is safe, make it. If uncertain, note it in the report.

### Analyze mode

Collect all violations found across every file and every practice skill. Do not make any code changes.

---

## Step 5: Report

### Fix mode report

Two sections:

**Refactored** — bullet list of specific changes made:
- `WorkspaceModel.swift`: Added `private(set)` to `repositories`, `selectedRepository`, `skills`
- `EvalRunnerModel.swift`: Replaced `registry.defaultEntry!` with guard + early return
- `CaseResult.swift`: Changed 9 `var` properties to `let`

**Unclear in Practice Docs** — cases where the practice skills didn't cover the situation clearly enough. Be specific; this helps improve the docs. Say "none" if there are none.

---

### Analyze mode report

One section per finding, sorted by severity (highest first). For each finding:

```
## [Severity N/10] <Brief title> — <FileName.swift>

**Location:** Lines <start>–<end>

**Why this is a problem**
<Explain how the code violates the rule and what concrete harm it causes —
maintenance burden, impossible state, broken reuse, etc. Connect the specific
code to the specific rule.>

**How to fix**
<A bounded, incremental change — not a rewrite. Include a brief code sketch
when it helps clarify the target state.>
```

End with a summary table:

| File | Findings | Highest severity |
|------|----------|-----------------|
| `Foo.swift` | 3 | 8/10 |
| `Bar.swift` | 1 | 4/10 |

And one sentence of overall assessment: what's the most important thing to address first and why.
