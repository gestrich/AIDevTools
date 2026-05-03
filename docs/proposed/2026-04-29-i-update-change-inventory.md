## Relevant Skills

| Skill | Description |
|-------|-------------|

## Background

`2026-04-29-b-release-process-change-inventory.md` documents every category of change made during the binary release pipeline effort. It contains four ⚠️ **Candidates for reevaluation** sections that were flagged as workarounds at the time. Plans d through g have now investigated each of those items and reached conclusions.

This plan updates the inventory to replace each ⚠️ candidate note with the actual outcome, making the document accurate as a reference for future toolchain upgrades.

**Prerequisites**: Plans d, e, f, and g must all be complete before running this plan.

---

## - [ ] Phase 1: Record outcomes in the change inventory

**Skills to read**: none

**File:** `docs/proposed/2026-04-29-b-release-process-change-inventory.md`

For each of the four ⚠️ candidates, replace the candidate note with a concluded status. Read the completed plan files (d, e, f, g) to determine which outcome was reached, then update accordingly.

**Section 3 — `--no-parallel` (from Plan d):**

Replace:
> **`--no-parallel`**: With the blocking tests already disabled via `.enabled(if: CI == nil)`, it is worth investigating whether `--no-parallel` is still necessary...

With one of:
- "Confirmed unnecessary as of `vX.Y.Z` / Swift X.Y. Removed in commit `<sha>`. Blocking tests disabled via `SystemTests` + `.enabled(if: CI == nil)` are sufficient."
- "Confirmed still required as of `vX.Y.Z` / Swift X.Y. `.enabled(if: CI == nil)` guards are insufficient — parallel execution deadlocks beyond `Process().waitUntilExit()`. Revisit on next toolchain update."

**Section 4 — `ConfigurationEditSheet.swift` `@ViewBuilder` extraction (from Plan e):**

Replace:
> **`c4409f0`** (`ConfigurationEditSheet.swift` `@ViewBuilder` extraction): A large refactor to work around a compiler crash...

With one of:
- "Confirmed unnecessary as of `vX.Y.Z` / Swift X.Y. Inlined `ForEach` bodies compile cleanly. Reverted in commit `<sha>`."
- "Confirmed still required as of `vX.Y.Z` / Swift X.Y. `setLocalDiscriminator` assertion still present in current toolchain. Revisit on next toolchain update."

**Section 4 — `InlineCommentView.swift` `if let` → `!= nil` (from Plan f):**

Replace:
> **`261e768`** (`if let x = x` → `x != nil`): This is a semantic change...

With one of:
- "Confirmed unnecessary as of `vX.Y.Z` / Swift X.Y. `if let x = x` compiles cleanly. Reverted in commit `<sha>`."
- "Confirmed still required as of `vX.Y.Z` / Swift X.Y. Unused-binding crash still present. Revisit on next toolchain update."

**Section 5 — Release tests in debug mode (from Plan g):**

Replace:
> **Release test mode**: The `release.yml` test job runs tests with no `-c release` flag (debug mode)...

With one of:
- "Confirmed unnecessary as of `vX.Y.Z` / Swift X.Y. `-c release` tests pass on both platforms. Updated in commit `<sha>`."
- "Confirmed still required as of `vX.Y.Z` / Swift X.Y. Signal-6 crash on `AIDevToolsKitMac` still present in release mode. Revisit on next toolchain update."

---

## - [ ] Phase 2: Commit and push

**Skills to read**: none

Commit the updated inventory and push to `main`:

```sh
git add docs/proposed/2026-04-29-b-release-process-change-inventory.md
git commit -m "Update release-process change inventory with investigation outcomes (Plans d-g)"
git push
```

No release is required for this plan — it is documentation only.
