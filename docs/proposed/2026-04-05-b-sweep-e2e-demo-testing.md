## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-enforce` | Enforces coding standards, architecture, and quality after code changes |

## Background

Over the last 24 hours, the sweep (formerly "maintenance") feature was added. Key capabilities:

- **Sweep chains** live in `claude-chain-sweep/<task-name>/` and iterate AI tasks over files matching a glob pattern, with cursor-based state that persists progress across batches.
- **Cursor tracking**: `state.json` records the last processed file; each new batch resumes from that cursor.
- **Multiple batches**: `config.yaml` sets `scanLimit` (files to scan per batch) and `changeLimit` (files to modify per batch), so a single invocation processes a controlled slice while successive invocations advance the cursor.
- **Skip detection**: files unchanged since the last sweep commit are automatically skipped via `git log` + blob hash comparison.
- **Spec chains** remain in `claude-chain/<project-name>/spec.md` — checkbox-driven, one PR per task.

### CLI entry points

| Command | What it does |
|---|---|
| `ai-dev-tools-kit claude-chain run-task --project <name>` | Full spec-chain run: checkout base, create branch, run AI, commit, push, create PR |
| `ai-dev-tools-kit claude-chain run-task --project <name> --staging-only` | Same but stops before push/PR |
| `ai-dev-tools-kit sweep run --task <dir> --repo <dir>` | Full sweep batch: branch, AI, commit, push, PR |
| `ai-dev-tools-kit sweep run --task <dir> --repo <dir> --dry-run` | Same but prints PR comment instead of posting |
| `ai-dev-tools-kit claude-chain status --repo-path <dir>` | Task progress (requires GitHub API) |

**Gap to address**: there is no local `list` command — `status` requires GitHub. If listing local chains is needed for testing, a `list` command must be added.

### AIDevToolsDemo repo

Located at `../AIDevToolsDemo` (relative to AIDevTools). Currently contains only a `README.md`. A GitHub remote exists (`gestrich/AIDevToolsDemo`).

The plan will set up real spec and sweep chains there and exercise them via CLI, applying fixes as bugs surface.

---

## Phases

## - [x] Phase 1: Create Demo App Chains

**Principles applied**: Created chain files directly without a setup wizard. Spec chain uses the same `configuration.yml`/`pr-template.md` pattern as existing chains in AIDevTools. Sweep `config.yaml` uses `filePattern: "src/**/*.txt"` with `scanLimit: 2` / `changeLimit: 1` as specified. Created 4 plain-text source files (`a.txt`–`d.txt`) for the sweep to process. Committed and pushed to `gestrich/AIDevToolsDemo` main.

**Skills to read**: 

Create both chain types in `../AIDevToolsDemo` by hand (no interactive setup wizard — direct file creation to keep it scriptable and repeatable).

### 1a — Spec chain: `hello-world`

Files to create in `../AIDevToolsDemo/claude-chain/hello-world/`:

- **`spec.md`** — three simple tasks that create/modify a file so each task is independently verifiable:
  ```markdown
  # Hello World

  Create text files as described in each task. Each file should contain exactly the specified content.

  ## Tasks

  - [ ] Create `output/hello-1.txt` containing the single line: `Hello World`
  - [ ] Create `output/hello-2.txt` containing the single line: `Hello Again`
  - [ ] Create `output/hello-3.txt` containing the single line: `Goodbye World`
  ```

- **`configuration.yml`** — set `assignee: gestrich` so PRs have an owner.

- **`pr-template.md`** — minimal template referencing `{{TASK_DESCRIPTION}}`.

### 1b — Sweep chain: `add-header`

Files to create in `../AIDevToolsDemo/claude-chain-sweep/add-header/`:

- **`spec.md`** — instructions telling AI to prepend a one-line comment to the matched file if none exists.
- **`config.yaml`**:
  ```yaml
  filePattern: "src/**/*.txt"
  scanLimit: 2
  changeLimit: 1
  ```

Create at least 4 test files in `../AIDevToolsDemo/src/` (e.g., `a.txt`, `b.txt`, `c.txt`, `d.txt`) with plain content so the sweep has something to process.

### 1c — Commit and push

```bash
cd ../AIDevToolsDemo
git add .
git commit -m "Add spec and sweep demo chains"
git push origin main
```

**Success criteria**: Both `claude-chain/hello-world/spec.md` and `claude-chain-sweep/add-header/config.yaml` exist on `main`; `git log` shows the commit.

---

## - [x] Phase 2: Test Spec Chain — Local Staging

**Skills used**: none
**Principles applied**: The installed `ai-dev-tools-kit` binary was stale and missing the `claude-chain` subcommand. Built and installed the release binary from source before running. All expected behaviours confirmed: branch created, `output/hello-1.txt` written with `Hello World`, changes committed, `spec.md` checkboxes unchanged, no PR created.

Exercise `run-task --staging-only` to prove spec-chain discovery, AI execution, and local commit work without touching GitHub PRs.

```bash
cd ../AIDevToolsDemo
ai-dev-tools-kit claude-chain run-task \
  --project hello-world \
  --staging-only
```

**Expected behaviour**:
1. CLI discovers `claude-chain/hello-world/spec.md` locally.
2. Fetches `main`, creates branch `claude-chain-hello-world-<hash>`.
3. Runs AI against Task 1.
4. AI creates `output/hello-1.txt` with content `Hello World`.
5. Changes are committed to the feature branch.
6. `spec.md` is **not** updated (spec.md checkbox update happens in finalize, which is skipped in staging mode — confirm this assumption; if it does update, note it).
7. No PR is created.

**Verify**:
```bash
git log --oneline -5
git diff main HEAD -- output/hello-1.txt
```

Fix any failures before proceeding. Commit fixes to AIDevTools with a message like `fix: spec chain staging-only for demo`.

---

## - [x] Phase 3: Test Spec Chain — Full PR Creation

**Skills used**: none
**Principles applied**: Two bugs surfaced and were fixed. (1) `CredentialResolver.getGitHubAuth()` only checked `GITHUB_TOKEN` env — if keychain had a different account's token (e.g. `bill_jepp`), that would override the shell `GH_TOKEN`, causing push auth failures. Fixed to check `GITHUB_TOKEN` then `GH_TOKEN` from env before falling back to keychain. (2) `gestrich/AIDevToolsDemo` lacked the `claudechain` label required by `PRStep` — created it as a one-time repo setup step. After fixes: three tasks ran across three invocations, each picking the next uncompleted branch-less task; three draft PRs created at gestrich/AIDevToolsDemo#1–3. PR body includes a "Task N/M:" prefix (by design in `RunChainTaskUseCase`). Multi-run skip detection confirmed: CLI skips tasks whose branch already exists on the remote.

Run the same chain without `--staging-only` to prove the full pipeline: branch → AI → commit → push → PR.

Before running, ensure the branch from Phase 2 is either deleted or the repo is on `main`:
```bash
git checkout main
```

Then:
```bash
ai-dev-tools-kit claude-chain run-task \
  --project hello-world
```

**Expected behaviour**:
1. Branch created, AI produces `output/hello-1.txt`.
2. Branch is pushed to GitHub.
3. PR opened against `main`.
4. CLI prints PR URL.

**Verify**:
```bash
gh pr list --repo gestrich/AIDevToolsDemo --label claudechain
```

Check that the PR diff contains `output/hello-1.txt` with the expected content.

Run a second time to confirm Task 2 is picked up (Task 1 hash already has an open PR, so it should be skipped):
```bash
ai-dev-tools-kit claude-chain run-task --project hello-world
```

Fix any failures. Commit fixes.

---

## - [x] Phase 4: Test Sweep Chain — First Batch

**Skills used**: none
**Principles applied**: Discovered and fixed a dry-run bug: `--dry-run` was passing `dryRun` only to `ChainPRCommentStep` but `PRStep` always ran, causing a real branch push and PR creation even in dry-run mode. Fix: conditioned `PRStep` on `!dryRun` in `RunSweepBatchUseCase`, and relaxed the `prNumber`/`prURL` guard in `ChainPRCommentStep` so it generates the comment preview without real PR context. The sweep did process `src/a.txt` (added `# auto-generated header`), committed a `[claude-sweep] cursor=src/a.txt` state commit, and created PR gestrich/AIDevToolsDemo#4. All verification criteria confirmed.

Run one batch of the sweep chain to prove file discovery, AI execution, cursor commit, and (if changes) PR creation.

```bash
cd ../AIDevToolsDemo
ai-dev-tools-kit sweep run \
  --task claude-chain-sweep/add-header \
  --repo . \
  --dry-run
```

Use `--dry-run` first to see what the PR comment would say without actually creating a PR.

**Expected behaviour**:
- CLI prints batch stats: tasks=2 (scanLimit=2), modifyingTasks≤1 (changeLimit=1), skipped=0.
- If changes made, PR comment printed to stdout.
- No PR created.

Then run without `--dry-run`:
```bash
ai-dev-tools-kit sweep run \
  --task claude-chain-sweep/add-header \
  --repo .
```

**Verify**:
- `claude-chain-sweep/add-header/state.json` exists and contains a non-null cursor.
- `git log --oneline -5` shows a `[claude-sweep] task=add-header cursor=...` commit.
- If changes made: `gh pr list --repo gestrich/AIDevToolsDemo` shows an open sweep PR.

Fix any failures. Commit fixes.

---

## - [x] Phase 5: Test Sweep Chain — Multiple Batches (Cursor Tracking)

**Skills used**: none
**Principles applied**: Merged the Phase 4 batch branch into main (rather than just closing the PR) so that `state.json` (cursor=src/a.txt) and the sweep commit history were present on main before running Batch 2. Batch 2 correctly resumed from b.txt (cursor advancement bypassed a.txt), modified b.txt, wrote a new cursor commit at `src/b.txt`, and created PR gestrich/AIDevToolsDemo#5. Two `[claude-sweep]` cursor commits confirmed in `git log`. No code fixes needed.

Close or merge the PR from Phase 4, then run the sweep again to prove the cursor advances and skip detection works.

```bash
# Merge or close the Phase 4 PR first
gh pr close <pr-number> --repo gestrich/AIDevToolsDemo  # or merge it

# Run batch 2
cd ../AIDevToolsDemo
git checkout main && git pull origin main
ai-dev-tools-kit sweep run \
  --task claude-chain-sweep/add-header \
  --repo .
```

**Expected behaviour**:
- Cursor resumes from where Batch 1 stopped (e.g., if Batch 1 stopped at `src/b.txt`, Batch 2 starts at `src/c.txt`).
- Files already processed and unchanged since the sweep commit are skipped.
- CLI prints new stats with updated cursor.

**Verify**:
```bash
cat claude-chain-sweep/add-header/state.json
# cursor should have advanced past Batch 1's cursor
git log --oneline -8
# should show two [claude-sweep] cursor commits
```

Fix any failures. Commit fixes.

---

## - [x] Phase 6: Add Missing CLI Commands

**Skills used**: none
**Principles applied**: Added `ListCommand` using `.local` source so it works without GitHub access. Supports optional `--kind spec|sweep|all` filter. Registered alphabetically between `FormatSlackNotificationCommand` and `ParseClaudeResultCommand` in `ClaudeChainCLI.swift`. The `status` command already accepts a `kind: ChainKind = .all` parameter in the service layer and the spec notes no `--kind` flag was blocked on during testing, so no change to `status` was needed.

During Phases 2–5, note any operations that require reading internal state but have no CLI command. Two known gaps:

- **Local chain list**: `status` requires GitHub. Add `ai-dev-tools-kit claude-chain list --repo-path <dir>` that calls `listChains(source: .local)` and prints project names + kind badges — useful for smoke-testing without network.
- **Sweep chain status**: Confirm `status` can surface sweep chains (see Phase 7); if a filtered view is needed add `--kind sweep` flag.

Only add commands actually blocked on during testing. Each new command follows existing patterns in `ClaudeChainCLI.swift` and is registered in `ClaudeChainCLI.configuration.subcommands`.

Commit any added commands: `feat: add claude-chain list command`.

---

## - [x] Phase 7: GitHub Status — Both Chain Types

**Skills used**: none
**Principles applied**: Fixed `GitHubChainProjectSource.fetchChainProject()` to detect sweep chains by checking if `basePath` starts with `ClaudeChainConstants.sweepChainDirectory` and setting `kindBadge = "sweep"` on both `ChainProject` return paths (empty-spec and normal). Updated `StatusCommand.printEnrichedProjectList()` to render the badge inline. Verified: `status --repo-path ../AIDevToolsDemo` shows `add-header [sweep]` and `hello-world` without a badge.

Run the `status` command against `AIDevToolsDemo` and verify it correctly surfaces both spec and sweep chains.

```bash
ai-dev-tools-kit claude-chain status \
  --repo-path ../AIDevToolsDemo
```

**Known gap to fix first**: `GitHubChainProjectSource.fetchChainProject()` constructs `ChainProject` without setting `kindBadge = "sweep"` for sweep chains. The local `SweepClaudeChainSource` hard-codes `kindBadge = "sweep"`, but the remote path never sets it, so `status` output won't distinguish sweep chains from spec chains, and `listChains(source: .remote, kind: .sweep)` returns nothing.

**Fix** (in `GitHubChainProjectSource`): after determining `basePath`, check whether it starts with `ClaudeChainConstants.sweepChainDirectory` and set `kindBadge = "sweep"` on the returned `ChainProject` accordingly.

After the fix, verify:
```bash
ai-dev-tools-kit claude-chain status --repo-path ../AIDevToolsDemo
# Should list:
#   hello-world   [░░░░░░░░░░░░░░░░░░░░]  0/3
#   add-header    [░░░░░░░░░░░░░░░░░░░░]  0/N  (sweep)
```

The sweep chain should appear with its "sweep" badge (or equivalent visual indicator in the `StatusCommand` output). If `StatusCommand` doesn't render the badge, add it.

Commit fix: `fix: set kindBadge=sweep in GitHubChainProjectSource`.

---

## - [x] Phase 8: Capacity Enforcement

**Skills used**: none
**Principles applied**: Fixed `RunChainTaskUseCase` to check capacity BEFORE creating the feature branch (previously checked after push, which allowed a branch to be created even when at capacity). Moved `repoSlug` detection and the capacity guard to right after `nextTask()`, guarded by `!options.stagingOnly` so staging-only runs skip the check. Removed the now-redundant post-push capacity block. Set `maxOpenPRs: 1` in `AIDevToolsDemo/claude-chain/hello-world/configuration.yml`. Verified: spec chain blocks with 1 open PR and succeeds after closing it; sweep chain blocks with open sweep PR and proceeds after closing it.

Verify that both chain types block new runs when capacity is reached.

### 8a — Spec chain capacity

Set `maxOpenPRs: 1` in `claude-chain/hello-world/configuration.yml`. With one open `claudechain`-labeled PR already on GitHub (from Phase 3), run:

```bash
ai-dev-tools-kit claude-chain run-task --project hello-world
```

**Expected**: CLI exits with an error or "at capacity" message — `PRStep` throws `PipelineError.capacityExceeded` because open PR count (1) equals `maxOpenPRs` (1). No new branch or PR should be created.

Then merge the open PR and re-run — it should succeed.

### 8b — Sweep chain capacity

With the sweep PR from Phase 4 still open:

```bash
ai-dev-tools-kit sweep run \
  --task ../AIDevToolsDemo/claude-chain-sweep/add-header \
  --repo ../AIDevToolsDemo
```

**Expected**: CLI exits immediately with `RunSweepBatchError.openPRExists` — "1 open PR(s) already exist with prefix 'claude-chain-add-header-'". No new branch.

Then close that PR and re-run — it should proceed.

Fix any failures (e.g., if capacity check isn't wired up properly for spec chains via the `run-task` path). Commit: `fix: capacity check for spec chain run-task`.

---

## - [x] Phase 9: PR Content + Summary Comment Verification

**Skills used**: none
**Principles applied**: Verified spec PR #6 and sweep PR #7. Spec chain title/body/comment all pass — body includes the `Task N/M:` prefix by design (documented in Phase 3). Sweep chain title/body/comment pass — fixed the redundant `[add-header]` that appeared twice in the sweep PR title (once from `PRStep`'s `projectName` prefix, once inside `batchDescription`). Fixed by removing the task name from `batchDescription` in `RunSweepBatchUseCase`, so the title is now `ClaudeChain: [add-header] Sweep: N file(s) updated, cursor at ...` instead of repeating `[add-header]`. Both PRs have AI-generated summary comments posted by `ChainPRCommentStep`.

After each chain type creates a PR, inspect the PR title, body, and summary comment to confirm they match the intended format.

### Spec chain PR

Expected title: `ClaudeChain: [hello-world] Create output/hello-1.txt containing the single line: \`Hello World\``
(truncated to 80 chars total if needed)

Expected body: the raw task description string.

```bash
gh pr view <pr-number> --repo gestrich/AIDevToolsDemo \
  --json title,body \
  --jq '{title: .title, body: .body}'
```

Expected comment: an AI-generated markdown summary of the diff, posted by `ChainPRCommentStep` via `gh pr comment`.

```bash
gh pr view <pr-number> --repo gestrich/AIDevToolsDemo --comments \
  | grep -A 20 "## "
```

### Sweep chain PR

Expected title: `ClaudeChain: [add-header] Sweep [add-header]: 1 file(s) updated, cursor at src/a.txt`

Note: the task name appears twice (`[add-header]` from `PRStep` prefix + `Sweep [add-header]:` from `batchDescription`). Decide whether to fix the redundancy or accept it; document the decision.

Expected body: the batch description string.

Expected comment: same AI-generated markdown summary via `ChainPRCommentStep`.

```bash
gh pr view <sweep-pr-number> --repo gestrich/AIDevToolsDemo \
  --json title,body \
  --jq '{title: .title, body: .body}'
```

If the comment is missing or empty, trace through `ChainPRCommentStep` — the AI diff summary may fail silently if the diff is empty or the step is not reached. Fix and commit: `fix: ensure sweep chain PR comment is posted`.

---

## - [x] Phase 10: Validation

**Skills used**: none
**Principles applied**: Ran all 14 validation rows via CLI. Skip detection (item 9) required resetting state.json cursor to null on main so the sweep would start from a.txt — the existing sweep commit "processed: src/a.txt" caused a.txt to be skipped, producing "1 task(s), 1 modifying, 1 skipped". All 14 rows passed. Sweep PR title fix from Phase 9 confirmed: new PR #8 title is "ClaudeChain: [add-header] Sweep: 1 file(s) updated, cursor at src/b.txt" (no redundant [add-header]).

All of the following should be provable by running CLI commands from `../AIDevToolsDemo`:

| Feature | Verification command |
|---|---|
| Spec chain discovers tasks locally | `run-task --staging-only` succeeds |
| Spec chain creates a PR | `gh pr list` shows claudechain PR |
| Spec chain picks next uncompleted task | Running twice produces different task branches |
| Spec chain respects capacity | Second run blocked when maxOpenPRs reached |
| PR title + body correct (spec) | `gh pr view --json title,body` matches expected format |
| PR summary comment posted (spec) | `gh pr view --comments` shows AI markdown summary |
| Sweep chain processes files in batches | First `sweep run` produces cursor commit + PR |
| Sweep cursor advances on second batch | Second `sweep run` cursor ≠ first cursor |
| Skip detection works | Third run (no file changes) logs `skipped > 0` |
| Sweep chain blocks when PR open | `sweep run` fails with `openPRExists` error |
| PR title + body correct (sweep) | `gh pr view --json title,body` matches expected format |
| PR summary comment posted (sweep) | `gh pr view --comments` shows AI markdown summary |
| `status` shows both chain types | `claude-chain status` lists hello-world and add-header |
| Sweep chain has correct badge in status | add-header shows "sweep" badge |

Run through this table top-to-bottom. For each row that fails, apply a targeted fix with a descriptive commit, then re-run.

End state: All rows pass with no manual intervention beyond running the CLI commands shown.

---

## - [x] Phase 11: Enforce Coding Standards

**Skills used**: `ai-dev-tools-enforce`
**Principles applied**: Ran enforce across all 6 Swift files changed during this plan. Fixed two silent `catch {}` blocks in `RunSpecChainTaskUseCase` (summary generation and PR comment posting) by adding `logger.warning` calls. Fixed silent `return 0` in `RunSweepBatchUseCase.countOpenSweepPRs` with a warning log. Renamed `RunChainTaskUseCase.swift` → `RunSpecChainTaskUseCase.swift` to match the primary type. Moved `ReviewOutput` from before the primary type to after it as `private struct`. Removed redundant `= nil` from `var prURL: String?`.

After all fixes are applied across Phases 2–10, run the enforce skill against every file changed in AIDevTools during this plan. This catches any quality, architecture, or build issues introduced by the fixes (e.g., the `kindBadge` fix in `GitHubChainProjectSource`, any new CLI commands, capacity-check fixes).

Use the `ai-dev-tools-enforce` skill to:
1. Check architecture layer violations
2. Check code quality (force unwraps, raw strings, fallback values)
3. Check build quality (warnings, dead code, TODO/FIXME left behind)
4. Check file/type organization

Apply any corrections as a final clean-up commit: `chore: enforce standards on sweep e2e fixes`.
