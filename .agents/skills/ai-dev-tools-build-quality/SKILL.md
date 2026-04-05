---
name: ai-dev-tools-build-quality
description: >
  Checks and fixes build quality issues in Swift code: compiler warnings in new or modified
  files, TODO/FIXME comments left in production code, commented-out code blocks, and debug
  artifacts (print statements, hardcoded test values, fatalError("not implemented"),
  temporary return statements). Use this whenever reviewing changed Swift files before
  committing, when asked to clean up code, or when ai-dev-tools-enforce is running.
user-invocable: true
---

# Build Quality

Your job is to **fix** build quality issues, not write a review. When you find a violation, make the change.

---

## Compiler Warnings

A warning-free build is a prerequisite for merging. Warnings become noise that hides real problems.

**Look for** in every new or modified file: unused variables, deprecated API calls, missing `@Sendable` annotations on closures passed to concurrent contexts, implicit `@MainActor` isolation mismatches.

**Fix:** Address every warning, even in code you didn't author. If a warning is in generated code or a dependency you cannot change, suppress it with a targeted attribute and add a comment explaining why.

---

## TODO and FIXME Comments

A comment that says "fix this later" and ships is a promise broken before it was kept.

**Look for:** `// TODO:`, `// FIXME:`, `// HACK:`, `// XXX:` in every new or modified file.

**Fix:**
- Complete the work now (preferred)
- Open a tracked issue and replace the comment with a link
- Delete the comment if the concern is no longer valid

Do not leave open-ended TODO comments in merged code.

---

## Commented-Out Code

Git history is the right place for removed code.

**Look for:** Blocks wrapped in `/* */`, lines prefixed with `//` that are clearly disabled code rather than explanatory, `#if false` blocks, unreachable `else` branches after `fatalError()`, dead `case` arms in exhaustive switches.

**Fix:** Delete entirely. If the code is disabled intentionally pending a decision, replace with a tracked issue reference.

---

## Debug Artifacts

**Look for:**
- `print(...)`, `debugPrint(...)`, `dump(...)`, `Swift.print(...)` added for debugging
- Hardcoded test values
- `fatalError("not implemented")` on paths reachable in production
- Temporary `return` statements that short-circuit logic during development

**Fix:** Remove debug prints or replace with structured logging via the project's logger (`Logger(label: "ClassName")`). Replace `fatalError("not implemented")` with a real implementation or `throw` an appropriate error. Remove hardcoded test values and use the actual data path.
