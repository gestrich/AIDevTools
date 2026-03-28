---
name: ai-dev-tools-review
description: >
  Reviews a Swift file for conformance to the 4-layer app architecture (Apps, Features, Services,
  SDKs). Detects which layer the file belongs to, loads the relevant reference doc, and reports the
  most egregious violations ranked by severity (1-10). Suggests practical, incremental refactors
  toward the ideal state — not massive rewrites. Use this skill when the user asks to review a file
  for architecture compliance, wants to know if code follows the layered architecture, asks "is this
  file structured correctly", or wants architectural feedback on Swift code. Also use when the user
  pastes or references a Swift file and asks for a review, audit, or critique.
user-invocable: true
---

# Architecture Review

Review a Swift file against the 4-layer architecture (Apps, Features, Services, SDKs) and report violations with practical, incremental fixes.

## Review Philosophy

Code reviews have a natural tendency toward justification — finding reasons why the current code is "ok" or "acceptable." This review skill takes the opposite stance. Its job is to identify how the code deviates from the ideal architecture and suggest concrete steps to move it closer.

That said, the review must be practical. A file with five architectural violations doesn't need a ground-up rewrite. Focus on the most egregious issues — the ones that cause the most pain or risk — and suggest incremental refactors that move the code toward the ideal state one step at a time. A minor refactor that addresses a major issue is far more valuable than a perfect refactor that never gets done.

The goal is iterative improvement: each review moves the codebase a little closer to where it should be.

## How to Conduct a Review

### Step 1: Identify the Layer

Read the file and determine which architectural layer it belongs to:

| Signal | Layer |
|--------|-------|
| `@Observable`, `@MainActor`, SwiftUI views, `AsyncParsableCommand`, server handlers | **Apps** |
| `UseCase` / `StreamingUseCase` conformance, multi-step orchestration | **Features** |
| Shared models, configuration, stateful utilities used across features | **Services** |
| Stateless `Sendable` structs, single-operation methods, no business concepts | **SDKs** |

Also consider the file's location in the directory structure (`apps/`, `features/`, `services/`, `sdks/`). When the file's location and its contents disagree, that's itself a finding worth reporting.

### Step 2: Load the Reference Doc

Based on the detected layer, read the corresponding reference:

| Layer | Reference |
|-------|-----------|
| Apps | [references/apps-layer.md](references/apps-layer.md) |
| Features | [references/features-layer.md](references/features-layer.md) |
| Services | [references/services-layer.md](references/services-layer.md) |
| SDKs | [references/sdks-layer.md](references/sdks-layer.md) |

If the file touches concerns from multiple layers (a common violation itself), read the references for all relevant layers.

### Step 3: Evaluate Against the Reference

Compare the file against the ideal patterns in the reference doc. For each violation found, assess:

1. **What's wrong** — the specific deviation from the architecture
2. **Severity (1-10)** — how much pain or risk this causes
3. **Suggested fix** — a practical, incremental refactor (not a rewrite)

#### Severity Scale

| Score | Meaning | Examples |
|-------|---------|---------|
| 9-10 | **Architectural boundary violation** — code is in the wrong layer entirely, or upward dependencies exist | Feature importing an App-layer module; SDK holding mutable state and business logic |
| 7-8 | **Structural violation** — code is in the right layer but violates a core principle | `@Observable` in a Feature; multi-step orchestration in a Service; app-layer model doing orchestration instead of calling a use case |
| 5-6 | **Design friction** — technically works but creates maintenance burden or coupling | Feature-to-feature dependency; SDK method that takes app-specific types; error swallowing in a Service |
| 3-4 | **Style/convention issue** — doesn't match established patterns | Wrong file organization order; non-alphabetical imports; unnecessary type aliases |
| 1-2 | **Minor nit** — cosmetic or very low impact | Naming doesn't follow `<Name><Layer>` convention; minor parameter ordering |

### Step 4: Write the Review Output File

Save the review to a file named `<FileName>.review.md` in the same directory as the reviewed file. For example, reviewing `ImportModel.swift` produces `ImportModel.review.md`.

The output file has a fixed structure with three sections per finding: **Guidance** (verbatim text from the reference doc showing the violated rule), **Interpretation** (why this code triggers that violation and justifies the severity score), and **Resolution** (the suggested incremental fix). Findings are sorted by severity, highest first.

Use this exact format:

````markdown
# Architecture Review: <FileName>.swift

**File:** `<full/path/to/File.swift>`
**Detected Layer:** <Apps | Features | Services | SDKs>
**Review Date:** <YYYY-MM-DD>

---

## Finding 1 — [Severity: N/10] <Brief title>

**Location:** Lines <start>-<end>

### Guidance

> <Verbatim quote from the reference doc describing the rule or principle that was violated.
> Copy the exact text — do not paraphrase. Include enough context that the reader
> understands the rule without needing to open the reference doc.>

### Interpretation

<Explain how the code in this file specifically violates the guidance quoted above.
Connect the dots between what the reference doc says and what the code actually does.
This is where you justify the severity score — why is this a N/10 and not higher or lower?>

### Resolution

<A concrete, incremental fix. Not "rewrite the file" — a specific, bounded change.
Include a brief code sketch when it helps clarify the target state.>

---

## Finding 2 — [Severity: N/10] <Brief title>

**Location:** Lines <start>-<end>

### Guidance

> <Verbatim quote from reference doc>

### Interpretation

<Explanation and severity justification>

### Resolution

<Incremental fix>

---

## Summary

| | |
|---|---|
| **Layer** | <detected layer> |
| **Findings** | <count> |
| **Highest severity** | <N/10> |
| **Overall health** | <one sentence assessment> |
| **Top priority** | <the single most impactful fix to make first> |
````

### Full Example

Here is a complete example of a review output file so the format is unambiguous:

````markdown
# Architecture Review: ImportModel.swift

**File:** `Sources/apps/MyMacApp/Models/ImportModel.swift`
**Detected Layer:** Apps
**Review Date:** 2026-03-28

---

## Finding 1 — [Severity: 8/10] Model orchestrates multiple SDK calls instead of using a use case

**Location:** Lines 24-35

### Guidance

> **Depth Over Width** — App-layer code calls **ONE** use case per user action.
> The use case orchestrates everything internally.
>
> **Rule:** If code coordinates multiple SDK/service calls, it belongs in a use case,
> not in an app-layer model or service.

### Interpretation

`startImport()` calls `apiClient.fetchData()`, `apiClient.submitImport()`, and
`apiClient.fetchStatus()` in sequence — three SDK calls orchestrated directly in the
model. This is the "width" anti-pattern: the model is doing the Features layer's job.
This rates 8/10 because it means the CLI cannot reuse this workflow, any future entry
point must duplicate the orchestration, and the model becomes responsible for keeping
state consistent across each step.

### Resolution

Extract the three-step sequence into a `StreamingUseCase` in
`features/ImportFeature/usecases/ImportUseCase.swift`. The model becomes:

```swift
func startImport(config: ImportConfig) {
    let prior = state.snapshot
    Task {
        do {
            for try await useCaseState in useCase.stream(options: .init(config: config)) {
                state = ModelState(from: useCaseState, prior: prior)
            }
        } catch {
            state = .error(error, prior: prior)
        }
    }
}
```

---

## Finding 2 — [Severity: 6/10] Multiple independent state properties instead of enum-based state

**Location:** Lines 5-9

### Guidance

> **Enum-based state** — model state is a single enum, not multiple independent properties.
>
> Enum-based `ModelState` with `prior` for retaining last-known data. View switches on
> model state — no separate loading/error properties.

### Interpretation

The model uses four separate properties (`isLoading`, `error`, `result`, `progress`)
rather than a single `ModelState` enum. This makes it possible to have inconsistent
combinations (e.g., `isLoading = true` while `result` is non-nil) and forces every view
to reason about each property independently. Severity 6/10 because it creates real
maintenance burden but doesn't cross a layer boundary.

### Resolution

Introduce a `ModelState` enum:

```swift
enum ModelState {
    case loading(prior: ImportSnapshot?)
    case ready(ImportSnapshot)
    case operating(ImportState, prior: ImportSnapshot?)
    case error(Error, prior: ImportSnapshot?)
}
```

Migrate one property at a time — start by combining `isLoading` and `result` into
`.loading` / `.ready(result)`, then fold in `error` and `progress`.

---

## Finding 3 — [Severity: 5/10] Error silently printed instead of surfaced to UI

**Location:** Lines 32-34

### Guidance

> **Propagate Errors — Don't Swallow Them** — Always propagate errors to callers rather
> than catching and ignoring them.
>
> **At the app layer**, catch errors to set state the UI can display.

### Interpretation

The `catch` block calls `print("import failed: \(error)")` but never updates model
state. The UI continues showing stale data with no indication that the operation
failed. Severity 5/10 because it silently hides failures from the user, but the
error is at least logged to the console.

### Resolution

Replace the print with a state update:

```swift
} catch {
    state = .error(error, prior: state.snapshot)
}
```

---

## Summary

| | |
|---|---|
| **Layer** | Apps |
| **Findings** | 3 |
| **Highest severity** | 8/10 |
| **Overall health** | Model is doing orchestration work that belongs in the Features layer, and state management uses scattered properties instead of an enum. |
| **Top priority** | Extract the multi-step SDK orchestration into an `ImportUseCase` — this unlocks CLI reuse and simplifies the model. |
````

### Handling Edge Cases

- **File spans multiple layers**: Report this as a high-severity finding. The fix is usually to extract code into the correct layer.
- **No violations found**: Write the output file with an empty findings section and a summary noting no violations.
- **File is too small to assess**: Note that limited code makes it hard to assess architectural compliance and flag anything you can see.
- **Unfamiliar architecture**: If the project doesn't appear to follow the 4-layer architecture, state that the review assumes this architecture and note what you observe instead.

## What This Review Does NOT Do

- **Functional correctness** — it doesn't check if the code works, only if it's architecturally sound
- **Performance review** — it doesn't evaluate algorithmic efficiency
- **Full code review** — it focuses on architectural compliance, not general code quality (though code-style violations from the architecture's style guide are in scope)
