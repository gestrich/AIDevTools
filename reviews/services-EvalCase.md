# Architecture Review: EvalCase.swift

**File:** `AIDevToolsKit/Sources/Services/EvalService/Models/EvalCase.swift`
**Detected Layer:** Services
**Review Date:** 2026-03-28

---

## Finding 1 — [Severity: 3/10] Mutable `suite` property to support post-decode mutation

**Location:** Lines 25

### Guidance

> **Shared models and types** — data structures used by multiple features
>
> Services hold shared models as value types (`struct`) with `Sendable` conformance.
> Value types should prefer immutable (`let`) properties to communicate intent and
> prevent accidental mutation.

### Interpretation

`suite` is declared as `var` solely so `CaseLoader` can mutate it after decoding
(`evalCase.suite = suite`). All other properties are `let`. This creates an inconsistency
in the struct's immutability contract — callers can't tell from the type signature which
properties are stable after construction. Severity 3/10 because the mutation site is
confined to a single place in CaseLoader and the struct is `Sendable`, but it's still
a convention issue for a shared model.

### Resolution

Change `suite` to `let` and add a `withSuite(_:)` copy method. Update `CaseLoader` to
use it:

```swift
// EvalCase
public let suite: String?

public func withSuite(_ suite: String) -> EvalCase {
    EvalCase(id: id, suite: suite, mode: mode, ...)
}

// CaseLoader
let evalCase = try decoder.decode(EvalCase.self, from: data)
cases.append(evalCase.withSuite(suite))
```

---

## Summary

| | |
|---|---|
| **Layer** | Services |
| **Findings** | 1 |
| **Highest severity** | 3/10 |
| **Overall health** | Clean service-layer model with correct layer placement, proper Sendable conformance, and no architectural boundary violations. The only issue is a mutable property used for post-decode patching. |
| **Top priority** | Change `suite` to `let` and add a copy method to eliminate the mutable property. |
