# Architecture Review: EvalRunnerModel.swift

**File:** `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/EvalRunnerModel.swift`
**Detected Layer:** Apps
**Review Date:** 2026-03-28

---

## Finding 1 — [Severity: 7/10] `loadLastResults()` does direct filesystem I/O instead of using a use case

**Location:** Lines 251-273

### Guidance

> **Minimal business logic** — models call use cases, not orchestrate multi-step workflows
>
> **Depth over width** — one user action = one use case call
>
> **Rule:** If code coordinates multiple SDK/service calls, it belongs in a use case,
> not in an app-layer model or service.

### Interpretation

`loadLastResults()` directly uses `FileManager`, `Data(contentsOf:)`, and `JSONDecoder` to scan the artifacts directory, iterate over registry entries, and decode `EvalSummary` JSON files. This is service/SDK-level work done inline in an Apps-layer model. The CLI has no equivalent capability — it can only run evals, not reload previous results. Severity 7/10 because this is multi-step filesystem orchestration that bypasses the Features layer entirely.

### Resolution

Extract into a `LoadLastResultsUseCase` in `Features/EvalFeature/`. The use case accepts an output directory and registry entries, returning `[EvalSummary]`. The model calls it in `init` and the CLI could reuse it.

---

## Finding 2 — [Severity: 6/10] `repoHasOutstandingChanges()` creates `GitClient` directly

**Location:** Lines 104-106

### Guidance

> **Minimal business logic** — models call use cases, not orchestrate multi-step workflows
>
> **Depth over width** — one user action = one use case call

### Interpretation

The model instantiates `GitClient()` inline on every call. While this is a single SDK call (not multi-step orchestration), it violates layering by reaching directly into the SDK from the Apps layer. `RunEvalsUseCase` already accepts `GitClient` as an injected dependency, making this inconsistency more visible. Severity 6/10 because it couples the model to a concrete SDK type and makes testing harder.

### Resolution

Inject `GitClient` via the initializer and store it as a private property. This aligns with how `RunEvalsUseCase` handles the same dependency.

---

## Finding 3 — [Severity: 5/10] `lastResults` exists outside the `State` enum

**Location:** Lines 46, 189-191

### Guidance

> **Enum-based state** — model state is a single enum, not multiple independent properties
>
> Enum-based `ModelState` with `prior` for retaining last-known data. View switches on
> model state — no separate loading/error properties.

### Interpretation

`lastResults: [EvalSummary]` lives as a separate property alongside the `State` enum. The `.completed` case also holds `[EvalSummary]`, meaning the same data is stored in two places. After `reset()` sets state to `.idle`, `lastResults` still holds old data — an inconsistent combination. Severity 5/10 because it creates real maintenance burden and makes state transitions non-atomic.

### Resolution

Add a `prior` parameter to `.idle`, `.running`, and `.error` cases to carry forward last results. Add a computed `lastResults` property on `State`. Remove the separate stored property.

---

## Finding 4 — [Severity: 5/10] `loadCaseOutput()` has force-unwraps and inline orchestration

**Location:** Lines 223-249

### Guidance

> **Propagate Errors — Don't Swallow Them** — Always propagate errors to callers rather
> than catching and ignoring them.
>
> **At the app layer**, catch errors to set state the UI can display.

### Interpretation

Lines 237-239 contain `registry.defaultEntry!` force-unwraps that will crash if no default entry exists. The method also has inline business logic for resolving qualified case IDs (lines 227-233) and building formatter options. The `try?` on line 248 silently swallows read errors. Severity 5/10 because the force-unwraps are crash risks and the error swallowing hides failures from the user.

### Resolution

Guard against nil `defaultEntry` and return nil early. The `try?` is acceptable here since the view handles nil output with a "No saved output found" message, but the force-unwrap must be fixed.

---

## Finding 5 — [Severity: 4/10] Debug logging infrastructure in model file

**Location:** Lines 8-23, scattered throughout `run()`

### Guidance

> **`@Observable` lives here and nowhere else** — models are `@MainActor @Observable class`
>
> **Minimal business logic** — models call use cases, not orchestrate multi-step workflows

### Interpretation

File-level `debugLogURL` and `debugLog()` functions write to `/tmp/eval_runner_debug.log`. The `run()` method has 10+ debug log calls that obscure the actual logic flow. This is infrastructure that doesn't belong in a model file. The `debugLogURL` initializer also eagerly truncates the file on module load. Severity 4/10 because it adds noise and couples the model to filesystem debugging, but doesn't violate layer boundaries.

### Resolution

Remove the debug logging infrastructure and all `debugLog()` calls. If persistent debug logging is needed, it should be in the use case's progress reporting, not the model.

---

## Finding 6 — [Severity: 4/10] Error swallowed in init

**Location:** Line 72

### Guidance

> **Propagate Errors — Don't Swallow Them** — Always propagate errors to callers rather
> than catching and ignoring them.
>
> **At the app layer**, catch errors to set state the UI can display.

### Interpretation

`try? listSuites.run(options)` silently discards the error. If suite loading fails, the user sees an empty list with no indication of what went wrong. Severity 4/10 because it hides a startup failure, but the consequence (empty list) is relatively benign.

### Resolution

Catch the error and set `state = .error(error)` so the UI can display an error banner.

---

## Finding 7 — [Severity: 3/10] Use cases not consistently injected

**Location:** Lines 65, 205, 248

### Guidance

> **Dependencies via init** — accept SDK clients and services through the initializer

### Interpretation

`RunEvalsUseCase` and `ListEvalSuitesUseCase` are injected via init, but `ClearArtifactsUseCase()` (line 205) and `ReadCaseOutputUseCase()` (line 248) are created inline on each call. This inconsistency makes the model harder to test and breaks the established pattern within the same file. Severity 3/10 because the inline use cases are stateless and simple, but consistency matters.

### Resolution

Inject `ClearArtifactsUseCase` and `ReadCaseOutputUseCase` via the initializer with default values, matching the pattern used for the other two use cases.

---

## Summary

| | |
|---|---|
| **Layer** | Apps |
| **Findings** | 7 |
| **Highest severity** | 7/10 |
| **Overall health** | Model has good enum-based state foundation but bypasses the Features layer for filesystem I/O, has scattered debug logging, and doesn't fully commit to the prior-carrying state pattern. |
| **Top priority** | Extract `loadLastResults()` into a `LoadLastResultsUseCase` and fold `lastResults` into the State enum — this eliminates the duplicated state and the layer violation in one move. |
