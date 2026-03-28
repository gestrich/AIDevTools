# Architecture Review: RepositoryEvalConfig.swift

**File:** `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/RepositoryEvalConfig.swift`
**Detected Layer:** Apps
**Review Date:** 2026-03-28

---

## Finding 1 — [Severity: 3/10] Missing `Sendable` conformance

**Location:** Lines 3-13

### Guidance

> **Shared models and types** — data structures used by multiple features
>
> Public model types in the Services layer ideal pattern show `Sendable` conformance:
> ```swift
> public struct ImportConfig: Sendable { ... }
> ```

### Interpretation

`RepositoryEvalConfig` has three `let` properties, all of type `URL` (which is `Sendable`). The struct is safely `Sendable` but doesn't declare it. All `UseCase.Options` types in the codebase conform to `Sendable`, and this config serves a similar role — a bundle of immutable values passed into async contexts (e.g., `EvalRunnerModel` uses it in `Task` blocks). Severity 3/10 because it works today due to implicit inference in some contexts, but explicitly declaring conformance is the project convention and enables safer cross-concurrency-boundary passing.

### Resolution

Add `Sendable` conformance:

```swift
struct RepositoryEvalConfig: Sendable {
```

---

## Finding 2 — [Severity: 2/10] Redundant explicit memberwise init

**Location:** Lines 8-12

### Guidance

> **Style/convention issue** — doesn't match established patterns
>
> Swift automatically synthesizes a memberwise initializer for structs. An explicit init that merely assigns each parameter to its corresponding stored property is redundant.

### Interpretation

The explicit `init(casesDirectory:outputDirectory:repoRoot:)` does nothing beyond what Swift's synthesized memberwise init already provides — no validation, no default values, no transformation. Removing it reduces boilerplate. Severity 2/10 because it's purely cosmetic with no architectural impact.

### Resolution

Remove the explicit init and rely on the synthesized memberwise initializer:

```swift
struct RepositoryEvalConfig: Sendable {
    let casesDirectory: URL
    let outputDirectory: URL
    let repoRoot: URL
}
```

---

## Summary

| | |
|---|---|
| **Layer** | Apps |
| **Findings** | 2 |
| **Highest severity** | 3/10 |
| **Overall health** | Clean, minimal data struct. No architectural violations — it bundles related URLs for the Mac app's eval workflow. Findings are minor convention issues only. |
| **Top priority** | Add `Sendable` conformance for consistency with the project's value-type conventions. |
