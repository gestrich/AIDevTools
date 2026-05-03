## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-enforce` | Run after code changes to verify standards and architecture |

## Background

Commit `261e768` changed an `if let x = x { ... }` pattern to `if x != nil { ... }` in `InlineCommentView.swift` to avoid a Swift 6.2 internal crash on unused `if let` bindings. The `if let` form is more idiomatic Swift; the `!= nil` form was purely a compiler-crash workaround.

This plan determines whether the underlying Swift 6.2 bug is still present. If fixed, reverting to `if let x = x` restores the more idiomatic pattern.

---

## - [ ] Phase 1: Attempt to revert the `!= nil` pattern

**Skills to read**: none

**File:** `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/PRRadar/Views/GitViews/InlineCommentView.swift`

1. Read the file and locate the `!= nil` check introduced by `261e768`.

2. Change it back to the original `if let x = x` binding pattern.

3. Build the Mac app locally:
   ```sh
   swift build --package-path AIDevToolsKit
   ```

**If build succeeds:** The Swift 6.2 unused-binding crash is resolved. Commit the revert — `if let x = x` is the idiomatic form and should be used.

**If build crashes (signal 6):** The bug is still present. Restore `x != nil` and add a one-line comment explaining it is a workaround for a Swift 6.2 compiler crash on unused `if let` bindings. Commit.

---

## - [ ] Phase 2: Push to `main` and verify CI

**Skills to read**: none

Push the committed change to `main` and confirm CI passes on both platforms:

```sh
git push
gh run watch --repo gestrich/AIDevTools
```

Both `Test (macos-latest)` and `Test (ubuntu-latest)` must pass before proceeding.

---

## - [ ] Phase 3: Release and validate AIDevToolsDemo

**Skills to read**: none

Cut a new release and verify the Linux binary works end-to-end in AIDevToolsDemo.

1. Confirm the working tree is clean:
   ```sh
   git status --porcelain
   ```

2. Check the latest release tag, then run the release script with the next version:
   ```sh
   gh release list --repo gestrich/AIDevTools --limit 5
   ./scripts/release.sh vX.Y.Z
   ```

3. Watch the full Release workflow and confirm all five jobs pass:
   ```sh
   gh run watch --repo gestrich/AIDevTools
   ```
   - `Test (macos-latest)`
   - `Test (ubuntu-latest)`
   - `Build macOS`
   - `Build Linux`
   - `Create Release`

4. Trigger the end-to-end binary test in AIDevToolsDemo:
   ```sh
   gh workflow run test-binary.yml --repo gestrich/AIDevToolsDemo -f version=vX.Y.Z
   gh run watch --repo gestrich/AIDevToolsDemo
   ```

5. Confirm all steps pass: Resolve version, Download release assets, Verify checksum, Verify attestation, Install binary, `ai-dev-tools-kit --help` exits 0, `ai-dev-tools-kit prradar --help` exits 0.
