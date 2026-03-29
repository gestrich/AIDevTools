## - [ ] Build the project and confirm zero warnings before merging

Run the project build and verify there are no compiler warnings in new or modified files. A warning-free build is a prerequisite for merging — warnings become noise that hides real problems.

Common sources: unused variables (`let _ =` fixable by removing the binding), deprecated API calls (update to the replacement), missing `@Sendable` annotations on closures passed to concurrent contexts, implicit `@MainActor` isolation mismatches.

Fix: address every warning, even if it appears in code you didn't author. If a warning is in generated code or a dependency you cannot change, suppress it with a targeted `// swiftlint:disable` or `@_silenced` attribute and add a comment explaining why.

---

## - [ ] Remove TODO and FIXME comments that were left in production code

Search for `// TODO:`, `// FIXME:`, `// HACK:`, and `// XXX:` in every new or modified file. A comment that says "fix this later" and ships is a promise that was broken before it was kept.

Fix: either complete the work now (preferred), open a tracked issue and replace the comment with a link to that issue, or delete the comment if the concern is no longer valid. Do not leave open-ended TODO comments in merged code.

---

## - [ ] Remove commented-out code and dead code blocks

Look for blocks of code wrapped in `/* */` or lines prefixed with `//` that are clearly commented-out rather than explanatory. Also look for `#if false` blocks, unreachable `else` branches after `fatalError()`, and dead `case` arms in exhaustive switches.

Fix: delete commented-out code entirely — git history is the right place for removed code. If the code is disabled intentionally pending a decision, replace the comment with a tracked issue reference. Dead code that is never reached should be removed or the control flow corrected so it is reachable.

---

## - [ ] Verify no debug artifacts were left in the code

Look for: `print(...)` statements added for debugging (not part of the intended logging strategy), `debugPrint(...)`, `dump(...)`, `Swift.print(...)`, hardcoded test values, `fatalError("not implemented")` on paths that can be reached in production, and temporary `return` statements that short-circuit logic during development.

Fix: remove debug prints or replace with structured logging using the project's established logger. Replace `fatalError("not implemented")` with a real implementation or `throw` an appropriate error. Remove hardcoded test values and use the actual data path.
