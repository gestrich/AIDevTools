# Architecture Review: SettingsModel.swift

**File:** `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/SettingsModel.swift`
**Detected Layer:** Apps
**Review Date:** 2026-03-28

---

## Finding 1 — [Severity: 5/10] Use case instantiated inline instead of injected

**Location:** Lines 9, 14

### Guidance

> **Minimal business logic** — models call use cases, not orchestrate multi-step workflows

> The model should hold use cases as stored properties injected at init, enabling testability and avoiding repeated instantiation.

### Interpretation

`ResolveDataPathUseCase()` is created fresh in three places: once in `init()`, and once every time `dataPath`'s `didSet` fires. While the use case is a stateless `Sendable` struct (so there's no correctness bug), this pattern bypasses dependency injection and makes the model impossible to test with a mock use case. It also means the model is tightly coupled to the concrete type. Severity 5/10 because it creates coupling and hurts testability but the use case is trivially cheap to construct.

### Resolution

Store the use case as a private property injected via `init`:

```swift
private let resolveDataPath: ResolveDataPathUseCase

init(resolveDataPath: ResolveDataPathUseCase = ResolveDataPathUseCase()) {
    self.resolveDataPath = resolveDataPath
    let resolved = resolveDataPath.resolve()
    self.dataPath = resolved.path
    resolveDataPath.save(resolved.path)
}
```

---

## Finding 2 — [Severity: 4/10] Hidden side-effect in didSet property observer

**Location:** Lines 7-11

### Guidance

> **Depth over width** — one user action = one use case call

### Interpretation

The `didSet` on `dataPath` silently calls `save()` on a freshly created use case every time the property changes. This is a hidden side effect — callers setting `dataPath` may not expect I/O to happen. The `updateDataPath` method already exists as the public API for changing the path, so the save logic should live there instead, making the side effect explicit and intentional. Severity 4/10 because it works but hides I/O behind a property setter.

### Resolution

Remove the `didSet` and move the save call into `updateDataPath`:

```swift
var dataPath: URL

func updateDataPath(_ newPath: URL) {
    dataPath = newPath
    resolveDataPath.save(newPath)
}
```

---

## Summary

| | |
|---|---|
| **Layer** | Apps |
| **Findings** | 2 |
| **Highest severity** | 5/10 |
| **Overall health** | A small, well-scoped model. Main issues are dependency injection and a hidden side-effect in `didSet`. |
| **Top priority** | Inject the use case and move save logic from `didSet` into the explicit `updateDataPath` method. |
