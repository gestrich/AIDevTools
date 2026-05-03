# Release Process Change Inventory

This document catalogs every category of change made during the binary release
pipeline effort (approximately 2026-04-25 through 2026-04-29). The work spanned
three plan files:

- `2026-04-26-b-binary-release-pipeline.md` — build, publish, install script
- `2026-04-26-c-pr-radar-use-release-binary.md` — migrate clients off build-from-source
- `2026-04-29-a-release-pipeline-with-tests.md` — wire real tests into release gating

Changes are grouped by type. Where a change may be worth revisiting, it is
flagged as **⚠️ Candidate for reevaluation**.

---

## 1. Linux Platform Guards (Package.swift and source files)

### What changed
Several Package.swift targets and a handful of source files were moved inside
`#if os(macOS)` blocks or given `#if canImport(Darwin)` guards because their
dependencies (SwiftUI, SwiftData, Combine, Darwin socket APIs, Security.framework)
do not exist on Linux.

**Key commits:**
| Commit | Change |
|--------|--------|
| `c60cc52` | Move `CLIMacCommands`, `GitUIToolkit`, `RepoExplorerFeature` + tests into `#if os(macOS)` block in Package.swift |
| `ddf2cb7` | Move `AppIPCSDK` into `#if os(macOS)` — uses Darwin socket APIs |
| `c37c734` | Move `ArchitecturePlannerService`/`ArchitecturePlannerFeature` into `#if os(macOS)` — imports SwiftData |
| `b5cd939` | Move `FileTreeService` into `#if os(macOS)` — uses Combine (`@Published`, `ObservableObject`) |
| `48d9c7f` | Guard `StreamLogsUseCase` with `#if canImport(Darwin)` — uses `LogFileWatcher` |
| `990d064` | Extract macOS-only CLI commands into a dedicated `CLIMacCommands` library target |
| `00987aa` | Guard `FileWatcherTests` with `#if canImport(Darwin)` |
| `a238b84` | Guard local diff monitor for Linux |
| `bcf6a77` | Gate file monitoring for Linux builds |

### Why these were done
`swift test` on Linux pulled in the full package graph and tried to compile
SwiftUI/SwiftData targets, which don't exist on Linux. The `#if os(macOS)` blocks
in Package.swift tell Swift Package Manager not to build those targets at all on
Linux. Source-level guards (`#if canImport(Darwin)`) were needed for files that
are part of Linux-compiled targets but reference Darwin-only APIs.

### Are they still necessary?
Yes. These guards correctly reflect real platform constraints. The underlying
dependencies (SwiftUI, SwiftData, Combine, Darwin sockets) will not be available
on Linux in the foreseeable future. Removing these guards would break the Linux
build.

---

## 2. Linux Test Behavioral Differences

### What changed
Several tests were failing on Linux due to behavioral differences between macOS
and Linux — not compilation failures, but wrong runtime behavior:

**Key commits:**
| Commit | Change |
|--------|--------|
| `82e8f27` | Fix `ClaudeSchemasTests` (`NSDictionary.isEqual` doesn't deep-compare on Linux); fix `SkillScannerTests` path comparison; guard `GitHubAppTokenServiceTests` with `#if canImport(Security)` |
| `79240dd` | Fix `SkillScanner` to strip trailing slash added by Linux's `FileManager.contentsOfDirectory` |
| `2b92bd7` | Fix `SkillScannerTests` path comparison (second iteration; `standardizedFileURL.path` + explicit strip) |
| `2cd2c93` | Add `#if canImport(Darwin) / #else` around `realpath` import in test files |
| `9c02aff` | Remove `Darwin.` module qualifier from `realpath` calls — unqualified works on both platforms |

### Why these were done
These are real cross-platform behavioral differences:

- **`NSDictionary.isEqual`**: on Linux, Foundation does not deep-compare nested
  `[String: Any]` dictionaries. Fixed by comparing JSON-serialized bytes instead.
- **Trailing slash**: Linux's `FileManager.contentsOfDirectory` appends a trailing
  slash to directory URLs; macOS does not. Fixed by normalizing paths before comparison.
- **`Security.framework`**: RSA signing uses `Security.framework`, which is
  macOS-only. Fixed by guarding the four signing tests with `#if canImport(Security)`.
- **`realpath`**: lives in `Darwin` on macOS and `Glibc` on Linux; using the
  unqualified name works on both.

### Are they still necessary?
Yes. The behavioral differences are real and the fixes are correct on both platforms.
The `SkillScanner` trailing-slash fix (commit `79240dd`) improves correctness of the
production code, not just the tests.

---

## 3. Test Parallelism / CI Deadlock Fixes

### What changed
The Swift Testing framework runs tests in parallel by default. On CI runners
(3 vCPUs, 6-thread cooperative thread pool), tests that call
`Process().waitUntilExit()` block cooperative threads and cause a total deadlock.
A multi-step approach was taken to resolve this:

**Key commits:**
| Commit | Change |
|--------|--------|
| `1d2491b` | Disable `GitWorkingDirectoryMonitorTests` on CI (FSEventStream unreliable on CI runners); fix `CommitListDiffModelTests` main-actor blocking |
| `343f8b7` | Fix `GitWorkingDirectoryMonitorTests`: cancel waiter task on timeout to unblock iterator |
| `ff3947a` | Revert the `withCheckedThrowingContinuation` approach in `CommitListDiffModelTests` — it caused an immediate hang |
| `b782371` | Move `LocalDiffServiceTests`, `GitWorkingDirectoryMonitorTests`, `CommitListDiffModelTests` to a new `SystemTests` target (macOS-only); add `.enabled(if: CI == nil)` to all blocking suites |
| `befef15` | Add `.enabled(if: CI == nil)` to `WorktreeFeatureTests` and `GitClientTests` blocking suites |
| `081ff52` | Skip `ExecuteChainUseCaseTests` on CI when local demo repo is absent |
| `9128264` | Fix `CostBreakdownTests` float precision issue and skip tests referencing `~/Desktop` fixture files |
| `92c0b47` | Add `--no-parallel` to macOS CI test command |
| `d747596` | Add `--no-parallel` to Linux CI test command |
| `14ef9da` | Fix race condition in `stopHaltsPipeline` test on Linux: replace fire-and-forget `Task { await pipeline.stop() }` with an `AsyncStream`-based signal so `stop()` is awaited deterministically |

### Why these were done
The root cause is that `Process().waitUntilExit()` is a blocking call that
occupies a thread in Swift's cooperative executor. With the parallel test runner
on a 3-vCPU CI machine, multiple such calls concurrently exhaust all available
threads and the executor deadlocks.

Two separate mitigations were applied:

1. **`--no-parallel`**: The blunt-instrument fix. Runs tests serially, eliminating
   the multi-thread blocking scenario entirely.

2. **`.enabled(if: CI == nil)` / `SystemTests` target**: The precise fix. Marks
   tests that call `Process().waitUntilExit()` so they only run locally (where
   the thread pool has more headroom). They are grouped in `SystemTests`, a
   macOS-only target.

Both mitigations coexist in the final state: `--no-parallel` is used *and* blocking
tests are disabled on CI.

### ⚠️ Candidates for reevaluation
**`--no-parallel`**: With the blocking tests already disabled via `.enabled(if: CI == nil)`,
it is worth investigating whether `--no-parallel` is still necessary. The comment
in `ci.yml` says "parallel execution still deadlocks on Swift 6.2 / macOS 14" even
after disabling blocking tests, which suggests there may be additional parallelism
issues beyond `Process().waitUntilExit()`. This should be tested: remove
`--no-parallel` and see if tests still pass on CI. If they do, `--no-parallel` can
be dropped for a faster test run.

**`ff3947a` (revert `CommitListDiffModelTests`)**: The `withCheckedThrowingContinuation +
DispatchQueue.global` approach was tried and reverted because it caused an immediate
hang. This test now calls `runGit` (blocking) directly. Since it lives in `SystemTests`
and is disabled on CI, this is safe, but if async alternatives for `Process` execution
are ever added, this test could be improved.

---

## 4. Swift 6.2 Compiler Crash Workarounds

### What changed
Several code patterns triggered abort/signal 6 crashes in the Swift 6.2 compiler.
These were worked around by changing the pattern that triggered the crash:

**Key commits:**
| Commit | Change |
|--------|--------|
| `261e768` | Replace unused `if let x = x` binding with `x != nil` in `InlineCommentView.swift` |
| `54067ba` | Remove unused `chainDir` variable in `RunSpecChainTaskUseCase.swift` |
| `88d1a99` | Change `var` to `let` in `AutoStartServiceTests.swift` |
| `4c42b7b` | Remove `@available(*, deprecated)` annotation from `AIRunSession.run(onOutput:work:)` |
| `98b5d76` | Fix deprecated `String(contentsOf:)` calls; remove unused import in `GeneratePlanUseCase.swift` |
| `c4409f0` | Extract `ForEach` bodies in `ConfigurationEditSheet.swift` to `@ViewBuilder` helper methods — workaround for Swift 6.2 `setLocalDiscriminator` assertion failure with complex binding view bodies |

### Why these were done
The Swift 6.2 compiler has known bugs where certain patterns (unused variables,
`@available(*, deprecated)` annotations, complex `ForEach` binding closures) trigger
an internal compiler abort rather than a diagnostic. CI was hitting these crashes
in the release-mode build. Changing the triggering pattern makes the compiler
succeed without changing the runtime behavior.

### ⚠️ Candidates for reevaluation
Several of these are workarounds, not improvements:

- **`261e768`** (`if let x = x` → `x != nil`): This is a semantic change. The
  original `if let` pattern is more idiomatic Swift. If the underlying Swift 6.2
  compiler bug is fixed in a future release, this could be reverted to `if let`.
  However, `x != nil` is not objectionably worse, so this may not be worth reverting.

- **`c4409f0`** (`ConfigurationEditSheet.swift` `@ViewBuilder` extraction): The
  ForEach body was refactored to avoid the `LocalDiscriminator` crash. The resulting
  code is ~94 lines of `@ViewBuilder` helpers. If the compiler bug is fixed upstream,
  the original inline version could be restored. Worth noting that the extracted
  helpers may actually be a readability improvement.

- **`54067ba`**, **`88d1a99`**: Removing unused variables / changing `var` to `let`
  are strictly correct improvements regardless of the compiler crash — these should
  not be reverted.

- **`4c42b7b`**, **`98b5d76`**: Removing deprecated API usage is correct practice
  regardless of the crash — these should not be reverted.

---

## 5. CI Workflow Strategy Evolution

### What changed
The CI workflow (`ci.yml`) and release workflow (`release.yml`) both went through
significant structural iteration before reaching their current shape:

**Evolution of `ci.yml`:**
| Commit | State |
|--------|-------|
| `c60cc52` | `ci.yml` first created; runs `swift test` on both platforms |
| `1747558` | Add 30-minute timeout to fail fast instead of hanging forever |
| `c8cc4dc` | Switch to `swift build` only on Linux; `swift test` on macOS |
| `88c825c` | Switch CI to `swift build` on *both* platforms (tests too broken to run) |
| `2c3fa8d` | Try `swift test` on macOS to measure actual runtime |
| `2beaaa8` | Increase CI timeout to 60 minutes for macOS `swift test` |
| `92c0b47` | Add `--no-parallel` on macOS |
| `d747596` | Add `--no-parallel` on Linux; switch Linux from `swift build` to `swift test` |
| `633e17f` | Add `::stop-commands::` wrapper to suppress spurious CI annotations |
| `f1239b8` | Add comment explaining `stop-commands` behavior |

**Evolution of `release.yml` test strategy:**
| Commit | State |
|--------|-------|
| Initial | `test` job ran `swift build` only (not real tests) |
| `e705159` | Install Swift 6.2 on macOS (runner ships 6.1) |
| `f3502bb` | Split test/build steps per-platform |
| `2677d3f` | Switch macOS to `swift build` in debug to avoid release-mode compiler crash |
| `5c5070b` | Update `release.yml` to run actual `swift test --no-parallel` on both platforms |

### Why these happened
The CI strategy was discovered iteratively because this was the first time `swift
test` was run in a clean, non-incremental environment on both platforms. Every
category of problem described in this document surfaced sequentially — a new
failure was only visible after fixing the previous one.

### ⚠️ Candidates for reevaluation
**Release test mode**: The `release.yml` test job runs tests with no `-c release`
flag (debug mode). The binary is then built with `-c release`. This means the
tests use different compiler settings than the released binary. If the release-mode
compiler crash (Swift 6.2 bug from `2677d3f`) is ever fixed, running tests in
release mode would provide stronger confidence that the released binary is correct.

---

## 6. Linux Static Stdlib Linking

### What changed
| Commit | Change |
|--------|--------|
| `d2b6d2b` | Add `--static-swift-stdlib` to Linux build command |
| `2d59530` | Add `libcurl4-openssl-dev libxml2-dev` pre-build step on Ubuntu |

### Why these were done
Without `--static-swift-stdlib`, the Linux binary linked against the Swift runtime
shared libraries (`.so` files). The build runner has Swift installed, but a
*different* runner (used for the `test-binary.yml` download-and-verify workflow)
does not. The binary crashed immediately on that runner.

Adding `--static-swift-stdlib` embeds the Swift runtime directly in the binary,
making it self-contained and runnable on any Ubuntu x86_64 machine without a Swift
installation. The static linker also needed `libcurl` and `libxml2` headers when
statically linking.

### Are they still necessary?
Yes. The whole point of the release binary is that clients can download and run it
without installing Swift. Removing `--static-swift-stdlib` would break that promise.

---

## 7. Pre-existing Test Failures Exposed by CI

### What changed
Several tests had been silently broken (or only passing due to incremental build
cache) and were discovered only when CI ran a clean build:

**Key commits:**
| Commit | What was broken |
|--------|----------------|
| `5dda549` | `RunAllUseCase.execute` was called with a stale `repo:` argument that no longer existed in the method signature |
| `c69ec4c` | `WorkflowServiceTests` mock was missing `readCacheRefreshState` and `writeCacheRefreshState` protocol methods |
| `2568067` | `MCPCommandTests` used internal types from `CLIMacCommands` without `@testable import` |
| `9128264` | `CostBreakdownTests.testToJSONIncludesReviewCost` was asserting `json.contains("0.3")` which was never true (float serialized as `0.29999...`); fixture file tests referenced `~/Desktop` paths |
| `081ff52` | `ExecuteChainUseCaseTests` referenced `/Users/bill/Developer/personal/claude-chain-demo` which only exists locally |

### Why these were done
These weren't changes related to the release process itself — they were pre-existing
bugs that had been masked by incremental local builds. The release CI's clean build
environment caught them. Fixing them was a prerequisite for getting CI green.

### Are they still necessary?
Yes. These are legitimate bug fixes that improve test correctness and reliability.
The stale argument fix (`5dda549`) fixed a real production code bug.

---

## 8. GitHub Attestations

### What changed
| Commit | Change |
|--------|--------|
| `720eaa7` | Add `actions/attest-build-provenance@v2` to `build-macos` and `build-linux` jobs; add verification step to `test-binary.yml`; add **Verifying the binary** section to README |
| `4db3e05` | Fix: add missing `attestations: write` + `id-token: write` to workflow-level permissions |

### Why these were done
`checksums.txt` proves the downloaded file is unmodified in transit, but doesn't
prove *where* it was built. GitHub Attestations cryptographically bind each release
asset to the exact Actions workflow run, commit SHA, and repo that produced it.
This is stored in GitHub's public transparency log and verifiable by any client with
`gh attestation verify`. It provides supply-chain provenance without managing GPG keys.

### Are they still necessary?
Yes. This is a security feature added intentionally. Removing it would degrade the
supply-chain integrity of releases.

---

## Summary Table

| Category | # Commits | Still necessary? | Reevaluation priority |
|----------|-----------|------------------|-----------------------|
| Linux platform guards (Package.swift) | ~9 | ✅ Yes | Low |
| Linux test behavioral differences | ~5 | ✅ Yes | Low |
| Test parallelism / CI deadlock | ~10 | Mostly yes | **Medium** (`--no-parallel` worth retesting) |
| Swift 6.2 compiler crash workarounds | ~6 | Mostly yes | **Medium** (some are stylistic tradeoffs) |
| CI workflow strategy evolution | ~9 | Yes (current state) | **Medium** (release tests in debug mode) |
| Linux static stdlib linking | 2 | ✅ Yes | Low |
| Pre-existing test failures | ~5 | ✅ Yes | Low |
| GitHub Attestations | 2 | ✅ Yes | Low |

### Top candidates for reevaluation

1. **`--no-parallel` on CI**: With blocking tests already disabled via
   `.enabled(if: CI == nil)`, test whether `--no-parallel` is still needed.
   If it can be removed, test runs will be faster.

2. **Release tests in debug mode**: If Swift 6.2's release-mode compiler crash
   is resolved in a future toolchain update, switch the `release.yml` test job
   to `-c release` to match the build mode of the published binary.

3. **`InlineCommentView.swift` `if let` → `!= nil` workaround** (`261e768`): A
   purely stylistic tradeoff. Revisit if the Swift 6.2 compiler bug is fixed.

4. **`ConfigurationEditSheet.swift` `@ViewBuilder` extraction** (`c4409f0`): A
   large refactor to work around a compiler crash. Revisit if the upstream bug
   is fixed, though the extracted helpers may be net-positive for readability.
