## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture — confirms `GitSDK` is the correct home for git CLI wrappers |

## Background

`ClaudeChainSDK` contains a `GitOperations` struct that is a hand-rolled process runner for git (and arbitrary shell) commands. The project already has `GitSDK` with a proper `GitClient` built on `CLISDK`/`CLIClient`, which handles working directory, argument construction, and async execution correctly.

`GitOperations` was the source of a bug where git commands ran in the wrong working directory because it spawned `Process` without setting `currentDirectoryURL`. Rather than patching `GitOperations`, we should remove it entirely and route all git usage through `GitClient`.

`GitOperations` also serves as a general-purpose process runner for non-git commands (used by `GitHubOperations` to run `gh`). That concern should be separated.

### Current callers of `GitOperations`

| Caller | Layer | Methods used | Sync/Async |
|--------|-------|-------------|------------|
| `GitHubOperations` | SDK | `runCommand` (for `gh`, not git) | Sync |
| `AutoStartService` | Feature | `detectChangedFiles`, `detectDeletedFiles`, `parseSpecPathToProject` | Sync |
| `FinalizeCommand` | App (CLI) | `runGitCommand` (checkout, add, commit, push, config, diff, rev-list, status) | Sync (`ParsableCommand`) |
| `PrepareCommand` | App (CLI) | `runGitCommand` (checkout) | Sync (`ParsableCommand`) |
| `SetupCommand` | App (CLI) | `runCommand` (git rev-parse) | Sync (`ParsableCommand`) |

## Phases

## - [x] Phase 1: Decouple `GitHubOperations` from `GitOperations`

**Skills to read**: `swift-architecture`

`GitHubOperations.runGhCommand` calls `GitOperations.runCommand` to shell out to `gh`. This is not a git operation — it shouldn't depend on `GitOperations` at all.

- Inline a minimal `runProcess` helper directly in `GitHubOperations` (or extract a tiny `ProcessRunner` utility in `ClaudeChainSDK`) that runs a `Process` and captures stdout/stderr.
- Update `GitHubOperations.runGhCommand` to use the new helper instead of `GitOperations.runCommand`.
- Update `SetupCommand` similarly — it calls `GitOperations.runCommand` for `git -C <path> rev-parse`. Replace with the same process helper or migrate to `GitClient`.

## - [x] Phase 2: Add missing git commands to `GitCLI` / `GitClient`

**Skills to read**: `swift-architecture`

The CLI commands in `FinalizeCommand` and `PrepareCommand` use git operations not yet in `GitClient`. Add them:

- `git config <key> <value>` — used by `FinalizeCommand` to set bot user
- `git remote set-url <name> <url>` — used by `FinalizeCommand` to set authenticated remote
- `git rev-list --count <range>` — used by `FinalizeCommand` to check commits ahead
- `git cat-file -t <ref>` — used by `ensureRefAvailable`
- `git fetch --depth=1 origin <ref>` — used by `ensureRefAvailable`
- `git diff --name-only --diff-filter=AM <ref1> <ref2> -- <pattern>` — used by `detectChangedFiles`
- `git diff --name-only --diff-filter=D <ref1> <ref2> -- <pattern>` — used by `detectDeletedFiles`

For `GitCLI` structs, add the `@CLICommand` definitions. For `GitClient`, add corresponding async methods.

## - [ ] Phase 3: Migrate `FinalizeCommand` and `PrepareCommand` to `GitClient`

**Skills to read**: `swift-architecture`

- Change `FinalizeCommand` from `ParsableCommand` to `AsyncParsableCommand`
- Change `PrepareCommand` from `ParsableCommand` to `AsyncParsableCommand`
- Replace all `GitOperations.runGitCommand(...)` calls with `GitClient` methods
- Add `GitSDK` dependency to `ClaudeChainCLI` target in `Package.swift` if not already present

## - [ ] Phase 4: Migrate `AutoStartService` to `GitClient`

**Skills to read**: `swift-architecture`

- `detectChangedFiles` / `detectDeletedFiles` logic moves into `GitClient` methods (or stays as a helper in `AutoStartService` that calls `GitClient`)
- `parseSpecPathToProject` is pure string parsing — move it to `ClaudeChainService` (e.g., on `Project`) since it's a domain concern, not a git concern
- `ensureRefAvailable` logic moves to a `GitClient` method
- Make `AutoStartService.detectChangedProjects` async

`AutoStartCommand` calls `detectChangedProjects` — verify it's already `AsyncParsableCommand` or migrate it.

## - [ ] Phase 5: Delete `GitOperations.swift` and clean up

- Delete `AIDevToolsKit/Sources/SDKs/ClaudeChainSDK/GitOperations.swift`
- Remove any now-unused imports of `ClaudeChainSDK` where only `GitOperations` was used
- Verify no remaining references to `GitOperations` in the codebase

## - [ ] Phase 6: Validation

**Skills to read**: `swift-testing`

- `swift build` succeeds with no errors
- `swift test` — all existing tests pass
- `grep -r "GitOperations" Sources/` returns no hits
- Run `swift run claude-chain run-task --project async-test --repo-path <demo-repo>` via CLI to verify the full chain still works end-to-end
