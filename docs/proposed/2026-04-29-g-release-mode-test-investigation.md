## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-enforce` | Run after code changes to verify standards and architecture |

## Background

The `release.yml` test job currently runs `swift test --no-parallel` without `-c release`. The published binary is built with `-c release`. This mismatch means a bug that only manifests under release-mode optimizations could ship undetected.

Commit `2677d3f` switched macOS tests to debug mode because `swift test -c release` triggered a signal-6 compiler crash on `AIDevToolsKitMac`. This plan determines whether that crash is still present in the current toolchain.

**Prerequisite**: Run Plan d (`2026-04-29-d`) first. This plan's `--no-parallel` decision must be known before editing `release.yml` — use the same setting here that Plan d arrived at for `ci.yml`.

---

## - [ ] Phase 1: Add `-c release` to `release.yml` test steps

**Skills to read**: none

**File:** `.github/workflows/release.yml`

1. Read the current `release.yml` test job.

2. Add `-c release` to both the macOS and Linux test steps in the `test` job. Apply the same `--no-parallel` decision from Plan d (include it if Plan d determined it is still needed; omit it if Plan d removed it):

   ```yaml
   - name: Test (macOS)
     if: matrix.os == 'macos-latest'
     run: swift test -c release --package-path AIDevToolsKit [--no-parallel if needed]

   - name: Test (Linux)
     if: matrix.os == 'ubuntu-latest'
     run: swift test -c release --package-path AIDevToolsKit [--no-parallel if needed]
   ```

3. Do not commit yet — first test with a pre-release tag (Phase 2).

---

## - [ ] Phase 2: Test with a pre-release tag

**Skills to read**: none

Push a pre-release tag to trigger the Release workflow without permanently publishing a release:

```sh
git add .github/workflows/release.yml
git commit -m "Test: add -c release to release.yml test steps"
git push
git tag v0.0.0-release-mode-test
git push origin v0.0.0-release-mode-test
```

Watch the `Release` workflow test matrix jobs:

```sh
gh run watch --repo gestrich/AIDevTools
```

Only the `test` matrix jobs matter here — the build and release jobs may fail or produce a draft, which is acceptable.

After observing results, delete the test tag regardless of outcome:

```sh
git push origin --delete v0.0.0-release-mode-test
```

**If both test jobs pass:** The release-mode compiler crash is resolved. Keep `-c release` in `release.yml`.

**If either test job fails with a signal-6 / compiler crash:** The bug is still present. Revert the `-c release` addition and add a comment in `release.yml` explaining that `-c release` causes a signal-6 crash on `AIDevToolsKitMac` under Swift 6.2, and should be retried when the toolchain is next updated.

Commit the final state and push to `main`.

---

## - [ ] Phase 3: Verify CI and release with AIDevToolsDemo

**Skills to read**: none

Confirm CI still passes cleanly, then cut a release and verify end-to-end.

1. Watch CI pass on both platforms after the Phase 2 commit:
   ```sh
   gh run watch --repo gestrich/AIDevTools
   ```

2. Confirm the working tree is clean: `git status --porcelain`

3. Check the latest release tag and run the release script with the next version:
   ```sh
   gh release list --repo gestrich/AIDevTools --limit 5
   ./scripts/release.sh vX.Y.Z
   ```

4. Watch the full Release workflow and confirm all five jobs pass (Test macOS, Test Linux, Build macOS, Build Linux, Create Release).

5. Trigger the end-to-end binary test in AIDevToolsDemo:
   ```sh
   gh workflow run test-binary.yml --repo gestrich/AIDevToolsDemo -f version=vX.Y.Z
   gh run watch --repo gestrich/AIDevToolsDemo
   ```

6. Confirm all steps pass: Resolve version, Download release assets, Verify checksum, Verify attestation, Install binary, `ai-dev-tools-kit --help` exits 0, `ai-dev-tools-kit prradar --help` exits 0.
