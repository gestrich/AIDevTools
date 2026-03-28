# Architecture Review: Skill.swift

**File:** `AIDevToolsKit/Sources/Services/SkillService/Models/Skill.swift`
**Detected Layer:** Services
**Review Date:** 2026-03-28

---

## Finding 1 — [Severity: 6/10] Redundant type duplication of SDK types

**Location:** Lines 1-27

### Guidance

> **Shared models and types** — data structures used by multiple features
>
> Services hold shared models used across features. They should not duplicate types already available from lower layers (SDKs).

### Interpretation

`Skill` and `ReferenceFile` are field-for-field duplicates of `SkillInfo` and `SkillReferenceFile` from `SkillScannerSDK`. Both have the same properties (`name`, `path`, `referenceFiles`, `source`), the same init signatures, and the same conformances (Skill actually has fewer — it lacks `Identifiable`). The rest of the codebase already uses `SkillInfo` directly (in EvalFeature, ChatFeature, AI SDKs, EvalService). The mapping in `LoadSkillsUseCase` is pure boilerplate that adds no value. This rates 6/10 because it creates unnecessary coupling and maintenance burden (two types to keep in sync) but doesn't violate a layer boundary.

### Resolution

1. Add `Identifiable` and `Hashable` conformances to `SkillReferenceFile` in SkillScannerSDK (to match what `ReferenceFile` provided).
2. Replace all uses of `Skill` with `SkillInfo` and `ReferenceFile` with `SkillReferenceFile`.
3. Simplify `LoadSkillsUseCase` to return `[SkillInfo]` directly without mapping.
4. Delete `Skill.swift`.

---

## Summary

| | |
|---|---|
| **Layer** | Services |
| **Findings** | 1 |
| **Highest severity** | 6/10 |
| **Overall health** | The file is a clean value type in the right layer, but it's an unnecessary duplicate of an existing SDK type that's already used directly elsewhere in the codebase. |
| **Top priority** | Eliminate the duplicate types by using `SkillInfo` and `SkillReferenceFile` from SkillScannerSDK directly. |
