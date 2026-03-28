# Architecture Review: MarkdownPlannerModel.swift

**File:** `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/MarkdownPlannerModel.swift`
**Detected Layer:** Apps
**Review Date:** 2026-03-28

---

## Finding 1 — [Severity: 5/10] Force unwrap on `providerRegistry.defaultClient`

**Location:** Lines 84-85

### Guidance

> **Error catching at this layer** — catch errors from use cases and set error state for UI display
>
> **Propagate Errors — Don't Swallow Them** — Always propagate errors to callers rather than catching and ignoring them.

### Interpretation

`providerRegistry.defaultClient!` will crash the app if no default provider is configured. The EvalRunnerModel review (Phase 4) specifically flagged identical force-unwraps on registry entries at severity 5/10 and replaced them with guards. This is the same pattern — a crash risk on a configuration edge case. Severity 5/10 because it's a crash risk in a recoverable situation, but likely only triggers during misconfiguration.

### Resolution

Guard against nil and either throw from init or fall back gracefully:

```swift
guard let client = selectedProviderName.flatMap({ providerRegistry.client(named: $0) })
    ?? providerRegistry.defaultClient else {
    fatalError("MarkdownPlannerModel requires at least one configured provider")
}
```

Or make init failable/throwing if the call site can handle it. Given the call site is a SwiftUI `State` initializer, `preconditionFailure` with a clear message is the pragmatic fix — it documents the requirement without changing the API surface.

---

## Finding 2 — [Severity: 5/10] `isLoadingPlans` is an independent boolean outside the State enum

**Location:** Lines 42, 98, 107

### Guidance

> **Enum-based state** — model state is a single enum, not multiple independent properties
>
> Enum-based `ModelState` with `prior` for retaining last-known data. View switches on model state — no separate loading/error properties.

### Interpretation

`isLoadingPlans` is a mutable boolean that can be `true` alongside any `State` case. For example, after `execute()` completes, the model sets `state = .completed(result)` then calls `loadPlans()` which sets `isLoadingPlans = true` — the model is simultaneously "completed" and "loading plans." While the independence may be intentional (plan list loading is orthogonal to execution state), the boolean is publicly settable and isn't `private(set)`. This matches the anti-pattern from prior reviews (ChatModel's `isLoadingHistory`/`isProcessing` booleans, severity 6/10). Severity 5/10 because it creates ambiguity but the orthogonal nature partially justifies separation.

### Resolution

Make `isLoadingPlans` `private(set)` to prevent external mutation, matching the access pattern of `lastExecutionPhases`. This is the minimal fix that preserves the orthogonal design while preventing misuse:

```swift
private(set) var isLoadingPlans: Bool = false
```

---

## Finding 3 — [Severity: 4/10] `lastExecutionPhases` stored as independent property instead of in State

**Location:** Lines 46, 174-176

### Guidance

> **Enum-based state** — model state is a single enum, not multiple independent properties
>
> Enum-based `ModelState` with `prior` for retaining last-known data.

### Interpretation

`lastExecutionPhases` is extracted from `ExecutionProgress` just before transitioning to `.completed`, then stored as a separate property. This data is logically part of the execution result but lives outside the state enum. After the model transitions to `.idle` (via `reset()`), `lastExecutionPhases` retains stale data from the previous execution. The EvalRunnerModel review (Phase 4) addressed the same pattern by folding `lastResults` into the State enum with a `prior` pattern. Severity 4/10 because the data is only read once (in `mergeExecutionPhaseStates`) and staleness has limited impact.

### Resolution

Add phases to the `.completed` case and provide a computed accessor:

```swift
case completed(ExecutePlanUseCase.Result, phases: [PhaseStatus])

var lastExecutionPhases: [PhaseStatus] {
    if case .completed(_, let phases) = self { return phases }
    if case .executing(let progress) = self { return progress.phases }
    return []
}
```

---

## Finding 4 — [Severity: 3/10] `executionProgressObserver` mutable closure bypasses @Observable pattern

**Location:** Lines 48, 308

### Guidance

> **`@Observable` lives here and nowhere else** — models are `@MainActor @Observable class`

### Interpretation

`executionProgressObserver` is a publicly settable closure that views assign to receive execution progress callbacks. This bypasses the `@Observable` pattern — instead of the view observing model state changes, the model pushes events to a callback. The view sets the closure before execution and nils it out after. This creates a manual observation mechanism alongside the automatic one. Severity 3/10 because the pattern works correctly and the alternative (piping fine-grained streaming output through state) would be more complex.

### Resolution

No code change recommended. The observer serves a legitimate purpose — bridging execution progress to a ChatModel for streaming display. Replacing it with state-based observation would require the model to store chat-specific streaming state, which would be a worse coupling. Document the intent:

```swift
/// Bridge for views to relay execution progress to a ChatModel for streaming display.
var executionProgressObserver: (@MainActor (ExecutePlanUseCase.Progress) -> Void)?
```

---

## Finding 5 — [Severity: 3/10] Event counter properties used for view triggers

**Location:** Lines 43-44

### Guidance

> **Enum-based state** — model state is a single enum, not multiple independent properties

### Interpretation

`executionCompleteCount` and `phaseCompleteCount` are integer counters incremented to trigger `.onChange(of:)` in SwiftUI views. They carry no semantic meaning — they exist solely as observation triggers. This is a common SwiftUI workaround for "fire-and-forget" events that don't map cleanly to state. Severity 3/10 because they work correctly and the alternative (e.g., an AsyncStream of events) would add complexity without clear benefit.

### Resolution

No code change recommended for the counters themselves. They're a pragmatic SwiftUI pattern. Making them `private(set)` would improve encapsulation:

```swift
private(set) var executionCompleteCount: Int = 0
private(set) var phaseCompleteCount: Int = 0
```

---

## Summary

| | |
|---|---|
| **Layer** | Apps |
| **Findings** | 5 |
| **Highest severity** | 5/10 |
| **Overall health** | Well-structured model with proper enum-based state, good use case delegation, and clear error handling. Main issues are a force-unwrap crash risk and a few state properties that leak outside the enum. |
| **Top priority** | Fix the force-unwrap on `providerRegistry.defaultClient` and tighten access control on independently stored properties. |
