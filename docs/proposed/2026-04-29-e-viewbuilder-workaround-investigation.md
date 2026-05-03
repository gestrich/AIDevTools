## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-enforce` | Run after code changes to verify standards and architecture |

## Background

Commit `c4409f0` extracted the `ForEach` bodies in `rulePathsSection` and `runCommandsSection` of `ConfigurationEditSheet.swift` into `@ViewBuilder` helper methods. This was a workaround for a Swift 6.2 `setLocalDiscriminator` assertion failure that crashed the compiler when `ForEach` closures contained complex binding-based view bodies. The extraction added roughly 94 lines of helper code.

This plan determines whether the underlying Swift 6.2 compiler bug is still present in the current toolchain. If fixed, the original inline structure can be restored. If still present, the helpers stay and get a comment referencing the upstream bug so it can be revisited on the next toolchain update.

---

## - [ ] Phase 1: Attempt to inline the `@ViewBuilder` helpers

**Skills to read**: none

**File:** `AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/PRRadar/Views/ConfigurationEditSheet.swift`

1. Read the current `ConfigurationEditSheet.swift` and identify the extracted `@ViewBuilder` helper methods introduced by `c4409f0`. They are used inside `ForEach` closures in `rulePathsSection` and `runCommandsSection`.

2. Inline the helper bodies back into the `ForEach` closures, restoring the structure that existed prior to `c4409f0`.

3. Build the Mac app locally:
   ```sh
   swift build --package-path AIDevToolsKit
   ```

**If build succeeds:** The Swift 6.2 `setLocalDiscriminator` bug is resolved in the current toolchain. Use judgment on whether to keep the inlined version — if the extracted helpers are genuinely more readable, restore them as a deliberate design choice rather than a workaround. Commit whichever version is preferred.

**If build crashes (signal 6 / assertion failure):** The bug is still present. Restore the `@ViewBuilder` helpers and add a comment explaining:
- The inline `ForEach` body triggered a `setLocalDiscriminator` assertion in Swift 6.2
- The helper extraction is a workaround, not a design choice
- Revisit when the toolchain is next updated

Commit the final state.

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
