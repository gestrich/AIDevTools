# Parallel CI Handoff: Fix macOS Test Hang

## The Goal

Get `swift test --package-path AIDevToolsKit` (no extra flags) to pass on **both** `macos-latest` and `ubuntu-latest` in CI, with:

- **All tests enabled** — no permanently disabled suites or individual tests
- **Full parallelism** — do NOT add `--no-parallel`, `--num-workers 1`, or any other flag that reduces concurrency. The entire point is to get parallel testing working.
- **Identical CI config for both platforms** — no macOS-specific workarounds in the workflow

The CI workflow is at `.github/workflows/ci.yml`. The test command is exactly:

```yaml
swift test --package-path AIDevToolsKit
```

That command — in that environment — must go green on both platforms.

---

## The Problem

macOS CI hangs for ~22 minutes and then gets cancelled at the 30-minute timeout. Linux (ubuntu-latest) passes fine. The same test binary works locally on macOS in seconds.

### Root Cause

Homebrew git 2.54.0 (used by `macos-latest` runners) treats an unconfigured remote name as a **hostname** and attempts SSH/DNS resolution. Several tests create temporary git repos and call git subprocesses. When those repos have no `origin` remote configured, git may try `ssh git@origin` — which hangs at the TCP/SSH level for ~22 minutes (the full timeout for an unreachable host).

This is made worse by `actions/checkout@v4`, which sets a **global** git config including `branch.autoSetupMerge=true`. This causes even simple operations like `git checkout -B <branch>` to implicitly probe the remote, triggering the hang.

The hang is **non-deterministic**: some CI runners return DNS NXDOMAIN quickly (test passes in seconds), others attempt a full TCP connection (hangs 22 minutes). That's why the same commit sometimes passes and sometimes fails on macOS.

Linux uses system git, which does not have this behavior — Ubuntu always passes.

---

## What Has Been Tried (Chronological)

All attempts are on the `main` branch of `gestrich/AIDevTools`. CI run IDs are from that repo.

### 1. Add `--no-parallel` (REJECTED — not the goal)
This was tried at the very start of this investigation and abandoned. It "fixes" the hang by serializing tests, but the goal is parallel tests. Do not do this.

### 2. `FileWatcher` fixes (runs ~25220xxx)
Early hangs were in `FileWatcher` tests under parallel load. Fixed by:
- Rewriting process termination to use async `terminationHandler` instead of blocking `.waitUntilExit()`
- Various `SwiftCLI` subprocess drain fixes (Linux pipe drains, GCD-based EOF)

After these fixes, Linux was stable. macOS still hung intermittently.

### 3. `.git/config` guards in test-facing code (commits 3f95293, 55d3802, 3168d1f)
Tests in `RunChainTaskUseCaseTests` create temp git repos and call `MarkdownClaudeChainSource.nextPendingStep()` and `ChainPRHelpers.detectRepo()`. Both of those called git subprocesses even when no `origin` was configured.

Fixed by:
- Reading `.git/config` directly via `String(contentsOfFile:)` to check if `[remote "origin"]` exists before calling any git subprocess
- If origin is not configured, skip the subprocess entirely and return an empty/default value

This removed several explicit git subprocess calls. But the hang continued.

### 4. `stagingOnly: true` flag in tests (commit 088ae0a)
Tests were calling `RunSpecChainTaskUseCase.run(...)` which eventually called `git push origin` — another subprocess that could hang. Added a `stagingOnly: true` option that short-circuits before the push. Tests were updated to use this.

This removed the `git push` call from tests. But the hang continued.

### 5. `GIT_TERMINAL_PROMPT=0` in `GitClient` (commit 228f4f6, run 25233297053)
Added `GIT_TERMINAL_PROMPT=0` to `GitClient`'s default subprocess environment to suppress interactive credential prompts. 

**Result**: Run 25233297053 was cancelled at 30m22s — still hanging. This env var prevents the UI prompt but does not prevent the underlying SSH TCP connection attempt.

### 6. `GIT_SSH_COMMAND` with `ConnectTimeout=5` (commit 5229497, run 25234534154)
Added `GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5"` to `GitClient`'s default subprocess environment. This limits any SSH connection attempt to 5 seconds max.

**Result**: Run 25234534154 — in progress at time of writing. Ubuntu passed. macOS status unknown.

This is the current state of the code. Check the CI run for its result.

---

## How to Work on This Using a Fork

1. **Fork `gestrich/AIDevTools`** on GitHub.
2. **Enable Actions** in your fork's Settings → Actions → Allow all actions.
3. Push commits to `main` (or any branch with a PR against `main`) — CI triggers automatically.
4. The CI config is already correct at `.github/workflows/ci.yml`. Do not change it.
5. Check runs at `https://github.com/<your-fork>/AIDevTools/actions`.

To trigger CI and observe the hang (before any fix), create a fresh fork from the commit just before commit `5229497` and push.

To verify a fix, your CI run must show **both** `Test (macos-latest)` and `Test (ubuntu-latest)` as **success** — not cancelled, not skipped.

---

## How to Identify the Hanging Test

If the current approach (`GIT_SSH_COMMAND` env var) still doesn't work, you need to find which test or suite is triggering the hang. Use **binary search**:

### Step 1: Get a baseline (reproduce the hang)
Push to a fork that lacks the fix. Confirm macOS hangs at ~22 minutes. Note the CI start time.

### Step 2: Disable half the test suites temporarily
In `AIDevToolsKit/Package.swift`, find all test targets. Comment out half of them (or add `.disabled()` to half the `@Suite` declarations). Push and see if macOS passes.

- If it **passes**: the hanging test is in the disabled half. Re-enable the disabled half and disable the previously-enabled half. Repeat.
- If it **still hangs**: the hanging test is in the enabled half. Keep narrowing.

### Step 3: Narrow to the individual test
Once you've identified the suite, binary search the individual tests within it using `.disabled()` on `@Test` declarations.

### Important: This is temporary scaffolding only
Do NOT submit a PR that has any tests permanently disabled. The binary search is to identify which test/suite is the problem so you can fix the underlying cause. All tests must be re-enabled in the final PR.

### Known suspect suites (most likely first)

1. **`RunSpecChainTaskUseCase`** — `Tests/Features/ClaudeChainFeatureTests/UseCases/RunChainTaskUseCaseTests.swift`
   - Creates temporary git repos in `initGitRepo(at:)`
   - Calls `useCase.run(...)` which drives `GitClient` methods
   - `preparedTaskProgress` and `progressThroughAIPhasesWithScriptsSkipped` both call git operations in temp repos without a configured remote
   - This is where CI logs showed activity just before the 22-minute silence

2. **`GitWorkingDirectoryMonitor`** — `Tests/SystemTests/GitWorkingDirectoryMonitorTests.swift`
   - Directly exercises git on a filesystem

3. **Any test that calls `GitClient` in a temp directory without configuring an origin remote**

---

## Where the Hang Is in the Code

When CI hangs, it's in `RunSpecChainTaskUseCase.run(...)` at:

```
AIDevToolsKit/Sources/Features/ClaudeChainFeature/usecases/RunSpecChainTaskUseCase.swift
```

The call sequence leading to the hang:

1. Test calls `useCase.run(options: .init(..., stagingOnly: true), ...)`
2. Use case reaches `git.checkout(ref: branchName, forceCreate: true)` (around line 271)
3. `GitClient.checkout()` calls `git checkout -B <branch>`
4. Homebrew git 2.54.0 sees `branch.autoSetupMerge=true` from the global config set by `actions/checkout@v4`
5. Git tries to contact `origin` — but no origin is configured, so it treats "origin" as a hostname
6. Git attempts `ssh git@origin` — which hangs at the TCP level for ~22 minutes

The `.git/config` guards in `MarkdownClaudeChainSource` and `ChainPRHelpers` address explicit `origin`-referencing calls. The `git checkout -B` hang is implicit — triggered by global git config, not by explicit origin references in the code.

---

## What a Valid Fix Looks Like

A valid fix must address the root cause without compromising test quality or parallelism. Some options:

### Option A: Set `GIT_SSH_COMMAND` + `GIT_TERMINAL_PROMPT` in all git subprocesses (already attempted)
This is what commit `5229497` does. It limits SSH timeouts to 5 seconds. Check if it worked. If yes, done.

### Option B: Set `GIT_CONFIG_NOSYSTEM=1` and `HOME=/dev/null` in test git repos
`GIT_CONFIG_NOSYSTEM=1` prevents git from reading `/etc/gitconfig`. Setting `HOME` to a temp empty dir prevents reading `~/.gitconfig`. This would block the global `branch.autoSetupMerge=true` from applying. **Risk**: may break tests that rely on git config being present.

### Option C: Explicitly unset `branch.autoSetupMerge` in `initGitRepo(at:)`
In `RunChainTaskUseCaseTests.initGitRepo(at:)`, add a git config command:

```swift
["config", "branch.autoSetupMerge", "false"],
```

This overrides the global setting in the local repo config and prevents the implicit remote lookup on `git checkout -B`.

### Option D: Set `GIT_CONFIG_COUNT` + `GIT_CONFIG_KEY_0` + `GIT_CONFIG_VALUE_0` environment variables
These env vars let you inject git config overrides per-process without touching files. Could be added to `GitClient.makeEnvironment()`:

```
GIT_CONFIG_COUNT=1
GIT_CONFIG_KEY_0=branch.autoSetupMerge
GIT_CONFIG_VALUE_0=false
```

This would prevent the implicit remote probe in any `git checkout -B` call through `GitClient`.

---

## Constraints

- **Do not** add `--no-parallel` or any concurrency-limiting flag to the test command
- **Do not** add `.disabled()` or `@available(*, unavailable)` to any test permanently
- **Do not** add `@Suite(.serialized)` to suites that don't already have it — serializing a suite is different from disabling it, but don't use it as a workaround
- **Do not** change the CI workflow in ways that hide the problem (e.g. `continue-on-error`, extra timeouts)
- **Do** verify your fix by checking that both matrix jobs (`macos-latest` and `ubuntu-latest`) show `success` in CI — not just one

---

## Delivering the Fix

Create a pull request against `gestrich/AIDevTools` `main` that:

1. Has a CI run where **both** `Test (macos-latest)` and `Test (ubuntu-latest)` are **success**
2. Contains no permanently disabled tests
3. Uses `swift test --package-path AIDevToolsKit` with no extra flags (same command as today)
4. Includes a brief description of the root cause and what the fix does

The CI workflow is the authoritative test environment. A fix that passes locally but not in CI is not done.
