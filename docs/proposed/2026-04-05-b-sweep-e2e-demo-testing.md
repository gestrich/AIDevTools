## Relevant Skills

| Skill | Description |
|-------|-------------|
| `claude-chain` | ClaudeChain chain management context |

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

**Skills used**: `claude-chain`
**Principles applied**: Created chain files directly without a setup wizard. Spec chain uses the same `configuration.yml`/`pr-template.md` pattern as existing chains in AIDevTools. Sweep `config.yaml` uses `filePattern: "src/**/*.txt"` with `scanLimit: 2` / `changeLimit: 1` as specified. Created 4 plain-text source files (`a.txt`–`d.txt`) for the sweep to process. Committed and pushed to `gestrich/AIDevToolsDemo` main.

**Skills to read**: `claude-chain`

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

## - [ ] Phase 2: Test Spec Chain — Local Staging

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

## - [ ] Phase 3: Test Spec Chain — Full PR Creation

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

## - [ ] Phase 4: Test Sweep Chain — First Batch

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

## - [ ] Phase 5: Test Sweep Chain — Multiple Batches (Cursor Tracking)

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

## - [ ] Phase 6: Add Missing CLI Commands

During Phases 2–5, note any operations that require reading internal state but have no CLI command. Two known gaps:

- **Local chain list**: `status` requires GitHub. Add `ai-dev-tools-kit claude-chain list --repo-path <dir>` that calls `listChains(source: .local)` and prints project names + kind badges — useful for smoke-testing without network.
- **Sweep chain status**: Confirm `status` can surface sweep chains (see Phase 7); if a filtered view is needed add `--kind sweep` flag.

Only add commands actually blocked on during testing. Each new command follows existing patterns in `ClaudeChainCLI.swift` and is registered in `ClaudeChainCLI.configuration.subcommands`.

Commit any added commands: `feat: add claude-chain list command`.

---

## - [ ] Phase 7: GitHub Status — Both Chain Types

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

## - [ ] Phase 8: Capacity Enforcement

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

## - [ ] Phase 9: PR Content + Summary Comment Verification

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

## - [ ] Phase 10: Validation

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
