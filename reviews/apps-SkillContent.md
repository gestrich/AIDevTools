# Architecture Review: SkillContent.swift

**File:** `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Models/SkillContent.swift`
**Detected Layer:** Apps (by location) / Services (by content)
**Review Date:** 2026-03-28

---

## Finding 1 — [Severity: 5/10] Pure data/parsing struct misplaced in Apps layer

**Location:** Lines 1-38

### Guidance

> **`@Observable` lives here and nowhere else** — models are `@MainActor @Observable class`
>
> The Apps layer contains platform-specific entry points: macOS apps (SwiftUI views + `@Observable` models), CLI tools (ArgumentParser commands), and server handlers. This is the **only layer** where `@Observable` and UI code belong.

### Interpretation

`SkillContent` is a plain `struct` that parses YAML front matter from a raw string. It has no `@Observable`, no `@MainActor`, no SwiftUI dependencies — it imports only `Foundation`. This is a data model / parser, not an app-layer model. It belongs alongside other skill types in `SkillService/Models/`. The `SkillDetailView` that consumes it already imports `SkillService`, so moving it requires no new dependencies. Severity 5/10 because the struct is small and only used in one place, but it's architecturally misplaced and prevents CLI reuse.

### Resolution

Move `SkillContent.swift` to `AIDevToolsKit/Sources/Services/SkillService/Models/SkillContent.swift`, make it `public`, and add `Sendable` conformance.

---

## Finding 2 — [Severity: 3/10] Missing Sendable conformance

**Location:** Line 3

### Guidance

> Shared models, configuration, stateful utilities used across features belong in **Services**.
> Value types in Services should be `Sendable`.

### Interpretation

`SkillContent` is a struct with only `let` properties (`[String: String]` tuple array and `String`), both of which are `Sendable`. The struct should explicitly conform to `Sendable` for concurrency safety. Severity 3/10 — minor convention issue since the type is already effectively Sendable.

### Resolution

Add `Sendable` conformance: `struct SkillContent: Sendable`.

---

## Summary

| | |
|---|---|
| **Layer** | Apps (by location), should be Services |
| **Findings** | 2 |
| **Highest severity** | 5/10 |
| **Overall health** | Small, well-written parsing struct that is simply in the wrong layer. |
| **Top priority** | Move to `SkillService/Models/` to match its nature as a shared data model. |
