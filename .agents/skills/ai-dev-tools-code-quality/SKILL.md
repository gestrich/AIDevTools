---
name: ai-dev-tools-code-quality
description: >
  Checks and fixes code quality issues in Swift: fallback values that hide failures,
  backwards-compatibility shims for unreleased code, raw String/[String:Any] types where
  typed models should exist, optional properties that should be non-optional, AI-changelog
  comments that describe what changed rather than why, duplicated logic across call sites,
  inline string formatting for derived identifiers (branch names, keys, paths),
  raw string literals used as shared identifiers, and force unwraps. Use when reviewing
  Swift code for quality, before committing, when asked to clean up or harden code,
  or when ai-dev-tools-enforce is running.
user-invocable: true
---

# Code Quality

Your job is to **fix** code quality issues, not write a review. When you find a violation, make the change.

---

## Fallback Values That Hide Failures

Fallback values can mask bugs — the caller never learns that the operation failed.

**Look for:**
- `?? ""`, `?? []`, `?? 0`, `?? false` on paths that should never be nil
- `guard ... else { return }` silently exiting when failure should be reported
- `try? expr ?? defaultValue` discarding the error silently

**Fix:** Replace fallbacks with `throws`, `guard let ... else { throw ... }`, or a `precondition`/`fatalError` with a clear message. Only keep a fallback if the default value is semantically correct (e.g., a preference with a genuine default).

---

## Backwards-Compatibility Shims for Unreleased Code

There is no backwards-compatibility obligation for code that has not shipped.

**Look for:**
- Deprecated `typealias` pointing to a new name
- `@available(*, deprecated, renamed: "...")` on types or methods that haven't shipped
- Old method signatures kept alongside new ones with a `// TODO: remove` comment
- Adapter or wrapper types that exist solely to bridge an old interface to a new one within the same codebase

**Fix:** Delete the shim entirely. Update all call sites to use the new API directly. If the call sites are in the same PR, there is no reason to keep both.

---

## Raw `String`, `[String: Any]`, and Untyped Dictionaries in APIs

**Look for:**
- Method signatures that accept or return `String` where a more specific type exists
- `[String: Any]` or `[String: String]` dictionaries
- `Any` parameters
- JSON-decoded results stored as dictionaries rather than `Decodable` structs

**Fix:** Define a `struct` or `enum` with named, typed fields. For identifiers, consider `struct FooID: RawRepresentable` rather than a bare `String` to prevent mixing up different ID spaces. For JSON responses, define a `Decodable` model.

---

## Optional Where Value Must Be Present

Optional should mean "this value genuinely may not exist." It should not mean "I wasn't sure how to get this at initialization time."

**Look for:**
- `var foo: Foo?` on properties always set during initialization
- Optional return types on methods that always return a value
- `init` parameters that are optional but required for the type to function

**Fix:**
- Value known at init time → non-optional stored property, require it in `init`
- Value not available at init → failable `init?` or `throws` rather than storing optional and checking it everywhere
- Value required for an operation → `guard let` at the call site and throw or return an error rather than silently doing nothing when nil

---

## AI-Changelog-Style Comments

Comments that describe what changed rather than what the code does become noise immediately after the PR merges.

**Look for:**
- `// Changed X to Y for new behavior`
- `// Added Z to support the new flow`
- `// Previously this was a class, now it's a struct`
- `// Updated to use the new API`
- `// Removed old implementation`

**Fix:** Delete the comment. If something genuinely needs explanation (a non-obvious algorithm, a workaround for a known bug, a performance trade-off), replace it with a comment that explains **why** the code does what it does, not what it used to do.

---

## Hidden Side Effects in Property Observers

A `didSet` or `willSet` that performs I/O or calls a use case is a hidden side effect — callers setting the property don't expect work to happen.

**Look for:** `didSet { useCase.save(...) }`, `didSet { fileManager.write(...) }`, or any `didSet` block that does more than update derived local state.

**Fix:** Remove the side effect from `didSet` and expose an explicit method. Callers that need the side effect call the method; callers that just want to set the value aren't surprised:

```swift
// BEFORE
var dataPath: String = "" {
    didSet { try? useCase.save(dataPath) }
}

// AFTER
private(set) var dataPath: String = ""

func updateDataPath(_ path: String) throws {
    dataPath = path
    try useCase.save(path)
}
```

---

## Redundant Explicit Memberwise Init

**Look for:** A `struct` with a hand-written `init` that exactly matches what Swift synthesizes — same parameter names, same types, same assignments, no defaulted parameters, no extra logic.

**Fix:** Delete the explicit init. Swift's synthesized memberwise initializer is identical and is always in sync with property additions or removals.

---

## Duplicated Logic

**Look for:**
- The same condition or predicate written in multiple places
- The same sequence of operations repeated across two use cases or services
- Identical `switch` arms or `if/else` chains in multiple files

**Fix:** Extract into a single function, computed property, or type that all sites call. For structural duplication across use cases, consider whether shared logic belongs in a Service. Do not create an abstraction for only two instances if they are likely to diverge — use judgment.

---

## Inline String Formatting for Derived Identifiers

String formatting logic for derived values — branch names, cache keys, file paths, URL paths — must live in one place. When callers construct these strings themselves, small differences in format accumulate silently and become hard to find.

**Look for:**
- `let branchName = "plan-\(identifier)"` or `"claude-chain-\(project)-\(hash)"` inline in a model or use case
- The same interpolation pattern appearing in more than one file
- A private helper method on a model that formats an identifier — the method likely belongs on the owning service or use case instead

**Fix:** Extract to a `static func` on the type that owns the concept. All callers use that method — no one builds the string themselves:

```swift
// BEFORE (inline in PlanModel, and potentially duplicated elsewhere)
let identifier = hashString(stem)
let branchName = "plan-\(identifier)"

// AFTER — single definition, all callers use it
// In PlanService (Features layer):
public static func worktreeBranchName(for planURL: URL) -> String {
    let stem = planURL.deletingPathExtension().lastPathComponent
    // ... hash ...
    return "plan-\(identifier)"
}

// In PlanModel:
let branchName = PlanService.worktreeBranchName(for: plan.planURL)
```

---

## Raw String Literals as Shared Identifiers

A string literal used in multiple places as an identifier (feature name, path component, dictionary key) is a coordination hazard. If one call site changes spelling, the others silently diverge.

**Look for:**
- `ServicePath.worktrees(feature: "plan")` and `ServicePath.worktrees(feature: "claude-chain")` repeated across files
- The same string literal appearing in both production code and tests
- Dictionary keys, UserDefaults keys, or notification names written as literals at each call site

**Fix:** Define a named constant — a `static var` on the owning type, a `static let` on the relevant service or model, or a dedicated `enum` of cases. All callers reference the constant, not the literal:

```swift
// BEFORE
dataPathsService.path(for: .worktrees(feature: "claude-chain"))
dataPathsService.path(for: .worktrees(feature: "plan"))

// AFTER — defined once on ServicePath
public extension ServicePath {
    static var claudeChainWorktrees: ServicePath { .worktrees(feature: "claude-chain") }
    static var planWorktrees: ServicePath { .worktrees(feature: "plan") }
}

// Callers
dataPathsService.path(for: .claudeChainWorktrees)
dataPathsService.path(for: .planWorktrees)
```

---

## Force Unwraps

A force unwrap is a bet that a condition is impossible. When that bet is wrong, it crashes in production.

**Look for:** `foo!`, `try!`, `as!` in non-test, non-IBOutlet production code.

**Fix:**
- `foo!` → `guard let foo else { throw FooError.missing }` or `guard let foo else { return }` with an appropriate error log
- `try!` → `try` with `throws` on the enclosing function, or `do/catch` that sets error state
- `as!` → `as?` with explicit handling of the nil case, or reconsider the type hierarchy so the cast is unnecessary
