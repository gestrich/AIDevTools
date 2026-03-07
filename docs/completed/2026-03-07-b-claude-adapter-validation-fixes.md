## Relevant Skills

No CLAUDE.md exists for this project. Existing codebase conventions serve as the guide.

## Background

During Phase 7 (Validation) of the skill-eval-integration plan, we attempted to run the example eval cases via the CLI against real providers (Claude and Codex). Codex worked immediately. Claude failed with `error: unknown option '--json-schema'`.

### Root cause discovered

The `CLIClient` (from the SwiftCLI dependency) resolves the `claude` binary by:
1. Checking common paths (`/usr/bin`, `/bin`, `/usr/local/bin`, `/opt/homebrew/bin`)
2. If not found, prepending nvm's node bin path to PATH, then running `which`

On Bill's machine, there are **two** `claude` installations:
- `/Users/bill/.nvm/versions/node/v22.17.0/bin/claude` — **v2.0.36** (old npm-installed version, does NOT support `--json-schema`)
- `/Users/bill/.local/bin/claude` — **v2.1.71** (current version, supports `--json-schema`)

The `CLIClient` finds the nvm version first because it prepends the nvm bin path to PATH before the `which` lookup.

### What was tried

1. Added `--debug` flag to `RunEvalsCommand` → plumbed through `RunEvalsUseCase.Options` → `ClaudeAdapter` to print exact CLI arguments and execution results
2. Confirmed the schema JSON was well-formed (compact, single-line) — not the issue
3. Confirmed environment variables (`CLAUDECODE`) were being stripped — not the issue
4. Identified from `printCommand` output that the resolved path was `/Users/bill/.nvm/versions/node/v22.17.0/bin/claude` (v2.0.36)

### Fix applied (partial)

Added `resolveClaudePath()` to `ClaudeAdapter` that checks `~/.local/bin/claude` first, then falls back to `"claude"`. Changed from `client.executeForResult(command, ...)` (typed command) to `client.execute(command: claudePath, arguments: command.commandArguments, ...)` (raw string command with explicit path).

This fixed the `--json-schema` error. Claude now runs successfully — first case produced output with exit code 0.

### Remaining issue

The `CLIClient.printCommand` output dumps the entire environment (all env vars) to stdout, which pollutes the eval output. The `printCommand: debug` flag causes massive output. This is cosmetic but noisy.

### What still needs to happen

- Run all 5 example evals with Claude provider end-to-end and confirm results
- Run existing unit tests to confirm nothing broke
- Rebuild Mac app
- Commit Phase 7 changes

## Phases

## - [x] Phase 1: Verify Claude adapter fix and suppress noisy output

**Skills used**: None
**Principles applied**: Investigated CLIClient environment merging behavior to find correct fix

**Changes made:**
- `ClaudeAdapter.swift`: Changed `printCommand: debug` → `printCommand: false` — our own `[DEBUG]` logging handles this already, and CLIClient's `printCommand` dumps the entire process environment which is very noisy
- `ClaudeAdapter.swift`: Changed `env.removeValue(forKey: ClaudeEnvironmentKey.claudeCode)` → `env[ClaudeEnvironmentKey.claudeCode] = ""` — CLIClient **merges** custom env on top of `defaultEnvironment` (which inherits from `ProcessInfo`), so removing a key from the custom dict has no effect. Setting to empty string bypasses Claude Code's nested session check.
- `.gitignore`: Added `Examples/evals/artifacts/` — these are generated output, not source
- Ran all 5 evals with both `--provider claude` and `--provider codex` — all complete without runtime errors. Failures are expected exact-match/rubric mismatches (Claude: 2 pass / 3 fail, Codex: 1 pass / 4 fail)

## - [x] Phase 2: Run unit tests and build Mac app

**Skills used**: None
**Principles applied**: Verified all unit tests pass and Mac app builds cleanly

- Run `swift test` in AIDevToolsKit — 109 tests passed. 8 pre-existing integration test failures (eval integration tests missing `result_schema.json` in temp dirs — unrelated to our changes)
- Run `xcodebuild build -scheme AIDevTools` — BUILD SUCCEEDED
- Confirm the new `debug` parameter defaults don't break existing callers (it defaults to `false`) — confirmed

## - [ ] Phase 3: Commit and mark Phase 7 complete

**All uncommitted changes to include:**
- `AIDevToolsKit/Sources/EvalSDK/ClaudeAdapter.swift` — env fix + printCommand fix + resolveClaudePath()
- `AIDevToolsKit/Sources/AIDevToolsKitApp/RunEvalsCommand.swift` — `--debug` flag
- `AIDevToolsKit/Sources/EvalFeature/RunEvalsUseCase.swift` — debug plumbing
- `AIDevToolsKit/Tests/EvalFeatureTests/RunEvalsUseCaseTests.swift` — new unit tests
- `.gitignore` — added `Examples/evals/artifacts/`
- `docs/proposed/2026-03-07-b-claude-adapter-validation-fixes.md` — this doc

**Steps:**
- Commit all the above with a message referencing Phase 7 validation
- Mark Phase 7 as complete in `docs/proposed/2026-03-07-a-skill-eval-integration.md`
- Since all phases in that spec will be complete, move it to `docs/completed/`
- Also move this spec (`2026-03-07-b-claude-adapter-validation-fixes.md`) to `docs/completed/`
