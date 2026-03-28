# Architecture Review: WorkspaceModel.swift

**File:** `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/WorkspaceModel.swift`
**Detected Layer:** Apps
**Review Date:** 2026-03-28

---

## Finding 1 — [Severity: 7/10] addRepository orchestrates multiple service/use-case calls

**Location:** Lines 95-118

### Guidance

> **Depth Over Width** — App-layer code calls **ONE** use case per user action.
> The use case orchestrates everything internally.
>
> **Rule:** If code coordinates multiple SDK/service calls, it belongs in a use case,
> not in an app-layer model or service.

### Interpretation

`addRepository()` calls `addRepository.run()`, `updateRepository.run()`,
`evalSettingsStore.update()`, and `planSettingsStore.update()` — four separate
service/use-case calls orchestrated directly in the model. This is the "width"
anti-pattern: the model is doing the Features layer's job.

This is compounded by the fact that `AddRepo` in the CLI duplicates the same
orchestration (lines 88-102 of ReposCommand.swift), confirming that this logic
belongs in a shared use case.

Severity 7/10 because the CLI cannot reuse this workflow without duplicating
the orchestration, and any future entry point must do the same.

### Resolution

Create a `ConfigureNewRepositoryUseCase` in SkillBrowserFeature that wraps the
add → update → settings dance. Both the model and CLI call the single use case.

```swift
public struct ConfigureNewRepositoryUseCase: Sendable {
    public func run(
        repository: RepositoryInfo,
        casesDirectory: String?,
        completedDirectory: String?,
        proposedDirectory: String?
    ) throws -> RepositoryInfo
}
```

---

## Finding 2 — [Severity: 7/10] removeRepository orchestrates multiple service/use-case calls

**Location:** Lines 132-145

### Guidance

> **Depth Over Width** — App-layer code calls **ONE** use case per user action.
> The use case orchestrates everything internally.

### Interpretation

`removeRepository()` calls `removeRepository.run()`, `evalSettingsStore.remove()`,
and `planSettingsStore.remove()` — three service calls in the model. The same
orchestration is duplicated in `RemoveRepo` CLI command (lines 116-128 of
ReposCommand.swift).

Severity 7/10 for the same reason as Finding 1: duplicated orchestration that
should be shared through a use case.

### Resolution

Create a `RemoveRepositoryWithSettingsUseCase` in SkillBrowserFeature:

```swift
public struct RemoveRepositoryWithSettingsUseCase: Sendable {
    public func run(id: UUID) throws
}
```

---

## Finding 3 — [Severity: 5/10] isLoadingSkills is a separate boolean outside the State enum

**Location:** Line 21

### Guidance

> **Enum-based state** — model state is a single enum, not multiple independent properties.
>
> Enum-based `ModelState` with `prior` for retaining last-known data. View switches on
> model state — no separate loading/error properties.

### Interpretation

The model has a `State` enum (idle/loading/loaded/error) but `isLoadingSkills` is a
separate `Bool`. This creates a secondary loading state tracked independently from the
main state, which can lead to inconsistent combinations (e.g., `state == .error` while
`isLoadingSkills == true`). Severity 5/10 because it creates maintenance burden but
is bounded to one extra property.

### Resolution

Make `isLoadingSkills` `private(set)` so views can read but not write it. This is the
minimum incremental fix. A future improvement could fold it into a sub-state or the
main state enum.

---

## Finding 4 — [Severity: 3/10] Loose access control on mutable properties

**Location:** Lines 18-21

### Guidance

> **Minimal business logic** — models call use cases, not orchestrate multi-step workflows.
>
> App-layer models should expose state for views to read, but mutations should go
> through model methods that update state consistently.

### Interpretation

`repositories`, `selectedRepository`, `skills`, and `isLoadingSkills` are all `var`
with implicit internal access. Views could mutate them directly, bypassing model
methods. Severity 3/10 because it's a convention issue — no known misuse, but
`private(set)` communicates intent and prevents accidental mutation.

### Resolution

Add `private(set)` to all four properties:

```swift
private(set) var repositories: [RepositoryInfo] = []
private(set) var selectedRepository: RepositoryInfo?
private(set) var skills: [Skill] = []
private(set) var isLoadingSkills: Bool = false
```

---

## Summary

| | |
|---|---|
| **Layer** | Apps |
| **Findings** | 4 |
| **Highest severity** | 7/10 |
| **Overall health** | Model is well-structured with enum-based state and dependency injection, but orchestrates multi-step operations that belong in use cases. The same orchestration is duplicated in CLI commands. |
| **Top priority** | Extract `ConfigureNewRepositoryUseCase` and `RemoveRepositoryWithSettingsUseCase` to eliminate model/CLI orchestration duplication. |
