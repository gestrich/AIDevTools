## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-enforce` | Enforces coding standards, architecture, and quality after code changes |

## Background

The directory walking feature was added to sweep chains in the commits preceding this plan (see `2026-04-05-d-sweep-directory-mode.md`). Key mechanics:

- **Mode detection**: a `filePattern` ending in `/` activates directory mode — e.g., `src/*/` walks immediate subdirs, `src/**/*/` walks all depths.
- **Directory enumeration**: `SweepClaudeChainSource.expandDirectories()` walks the repo and filters dirs against the glob, sorted alphabetically.
- **Task instructions**: instead of `File: <path>`, the AI receives `Directory: <path>` so it knows it's operating on a whole folder.
- **Skip detection**: `canSkipDirectory()` runs `git diff --name-only <cursorCommit> HEAD <dir>` — empty output means no files inside changed, so skip.
- **Cursor mechanics**: identical to file mode — the cursor is the last processed directory path, persisted in `state.json`.

The `AIDevToolsDemo` repo (`../AIDevToolsDemo` relative to AIDevTools) already has a flat `src/` with `a.txt`–`d.txt` and a file-mode sweep chain (`add-header`). This plan sets up subdirectories and a new directory-mode sweep chain to exercise the feature end-to-end.

### CLI entry points (unchanged from file mode)

| Command | What it does |
|---|---|
| `ai-dev-tools-kit sweep run --task <dir> --repo <dir>` | Full sweep batch: branch, AI, commit, push, PR |
| `ai-dev-tools-kit sweep run --task <dir> --repo <dir> --dry-run` | Prints PR comment instead of posting |
| `ai-dev-tools-kit claude-chain list --repo-path <dir>` | Lists chains locally |
| `ai-dev-tools-kit claude-chain status --repo-path <dir>` | GitHub-enriched status |

---

## Phases

## - [x] Phase 1: Set Up Directory Structure and Sweep Chain

**Skills used**: none
**Principles applied**: Created directories and sweep chain files directly in AIDevToolsDemo on main branch; stashed in-progress branch work to keep the commit clean on main.

Create subdirectories in `../AIDevToolsDemo/src/` and a new directory-mode sweep chain. The existing flat files (`a.txt`–`d.txt`) stay untouched — they should not appear in a `src/*/` enumeration (files are excluded, only directories match).

### 1a — Create four source directories

```bash
cd ../AIDevToolsDemo
mkdir -p src/alpha src/beta src/gamma src/delta
echo "Alpha module source" > src/alpha/main.txt
echo "Beta module source"  > src/beta/main.txt
echo "Gamma module source" > src/gamma/main.txt
echo "Delta module source" > src/delta/main.txt
```

### 1b — Create a nested subdirectory (for Phase 5 recursive test)

```bash
mkdir -p src/alpha/subdir
echo "Alpha subdir content" > src/alpha/subdir/extra.txt
```

### 1c — Create sweep chain `add-dir-readme`

Files to create in `../AIDevToolsDemo/claude-chain-sweep/add-dir-readme/`:

**`spec.md`**:
```markdown
# Add Directory README

Add a `README.md` file to the given directory if none already exists.
The README should contain a single line: `# <DirectoryName>` where `<DirectoryName>`
is the last path component of the directory (e.g., `alpha` → `# alpha`).
Do not modify any existing files.
```

**`config.yaml`**:
```yaml
filePattern: "src/*/"
scanLimit: 2
changeLimit: 1
```

### 1d — Commit and push

```bash
cd ../AIDevToolsDemo
git add .
git commit -m "Add directory structure and add-dir-readme sweep chain"
git push origin main
```

**Success criteria**:
- `ls src/` shows `alpha/`, `beta/`, `gamma/`, `delta/` alongside the existing flat files.
- `cat claude-chain-sweep/add-dir-readme/config.yaml` shows `filePattern: "src/*/"`.
- `git log --oneline -1` shows the commit.

---

## - [x] Phase 2: Verify Directory Enumeration (Dry Run)

**Skills used**: none
**Principles applied**: Fixed `--dry-run` to enumerate candidates without creating branches, running the AI, or committing — previously it only skipped PR creation. Added `candidatesForNextBatch()` to `SweepClaudeChainSource` and a `runDryRun` path in `RunSweepBatchUseCase` that respects `scanLimit`. Added a public memberwise initializer to `SweepBatchStats`. Debug investigation revealed the release binary was outdated (prior `swift build` installed from debug path); fixed by building with `-c release`.

Run a dry-run to confirm that directory mode enumerates subdirectories and not flat files, and that the task instructions say `Directory:` not `File:`.

```bash
cd ../AIDevToolsDemo
ai-dev-tools-kit sweep run \
  --task claude-chain-sweep/add-dir-readme \
  --repo . \
  --dry-run
```

**Expected behaviour**:
- CLI prints batch stats. `scanLimit=2` so at most 2 directories are considered.
- Output references `src/alpha` and `src/beta` (alphabetical order) — not `src/a.txt` or other flat files.
- The PR comment preview (if any dirs would be modified) references `Directory: src/alpha`.
- No branch, commit, or PR is created.

**Verify** by inspecting stdout. If the dry-run output is minimal, add a brief `--verbose` or read the log output to confirm the paths enumerated.

If flat files appear in the enumeration (regression), investigate `expandDirectories()` in `SweepClaudeChainSource.swift` — the directory filter must exclude non-directory filesystem entries.

Fix any failures. Commit fixes to AIDevTools.

---

## - [x] Phase 3: First Batch — Directory Mode PR

**Skills used**: none
**Principles applied**: Ran the first real sweep batch; all expected outputs matched without any fixes needed — cursor advanced to `src/alpha`, `README.md` created with correct content, PR #9 opened with correct title and `claudechain` label.

Run the first real batch to produce a branch, AI-generated `README.md`, commit, and PR.

```bash
cd ../AIDevToolsDemo
git checkout main && git pull origin main
ai-dev-tools-kit sweep run \
  --task claude-chain-sweep/add-dir-readme \
  --repo .
```

**Expected behaviour**:
1. CLI enumerates `src/alpha`, `src/beta` (scanLimit=2). Processes `src/alpha` (changeLimit=1 — stops after one modification).
2. AI creates `src/alpha/README.md` containing `# alpha`.
3. Changes committed: `Sweep [add-dir-readme]: src/alpha`.
4. Cursor commit written: `[claude-sweep] task=add-dir-readme cursor=src/alpha`.
5. Branch pushed and PR opened against `main`.

**Verify**:
```bash
# Cursor advanced to src/alpha
cat claude-chain-sweep/add-dir-readme/state.json
# Should show: "cursor": "src/alpha"

# Cursor commit present
git log --oneline -4
# Should show two commits: [claude-sweep] cursor and Sweep [...] src/alpha

# PR exists
gh pr list --repo gestrich/AIDevToolsDemo --label claudechain
```

Also confirm the PR diff contains `src/alpha/README.md` and that the PR title follows the pattern `ClaudeChain: [add-dir-readme] Sweep: 1 file(s) updated, cursor at src/alpha`.

Fix any failures. Commit fixes to AIDevTools.

---

## - [x] Phase 4: Cursor Advancement — Second Batch

**Skills used**: none
**Principles applied**: Fixed `canSkipDirectory()` bug — it was skipping unprocessed directories because it only checked `hasDirectoryChanges` without first verifying the directory appeared in the `processed:` list of the cursor commit. Made it match the `canSkip()` file-mode logic: guard on `processedDirs.contains(path)` before the git-diff check. The initial bad run (cursor advanced to `src/gamma` with 0 tasks) was discarded by deleting the local branch before re-running with the fixed binary.

Merge the Phase 3 PR so `state.json` (cursor=`src/alpha`) is on `main`, then run a second batch to prove the cursor advances past `src/alpha` to `src/beta`.

```bash
# Merge Phase 3 PR (keeps cursor commit on main)
gh pr merge <pr-number> --repo gestrich/AIDevToolsDemo --merge

cd ../AIDevToolsDemo
git checkout main && git pull origin main

ai-dev-tools-kit sweep run \
  --task claude-chain-sweep/add-dir-readme \
  --repo .
```

**Expected behaviour**:
- Cursor resumes from `src/alpha` → next directory is `src/beta`.
- AI creates `src/beta/README.md` containing `# beta`.
- New cursor commit: `cursor=src/beta`.
- New PR opened.

**Verify**:
```bash
cat claude-chain-sweep/add-dir-readme/state.json
# Should show: "cursor": "src/beta"

git log --oneline -6
# Should show two [claude-sweep] cursor commits total
```

Fix any failures.

---

## - [x] Phase 5: Skip Detection — Unchanged Directories

**Skills used**: none
**Principles applied**: Fixed two bugs: (1) `canSkipDirectory` only checked the most recent cursor commit — added `logGrepAll` to `GitClient` to search all cursor commits for the path. (2) `runDryRun` bypassed skip detection entirely (called `candidatesForNextBatch()` which is synchronous and skip-unaware) — added `dryRunStats()` to `SweepClaudeChainSource` that applies the `scanLimit` window with skip detection. Also suppressed raw git output in sweep CLI by initializing `GitClient(printOutput: false)` in `SweepCommand`.

After merging the Phase 4 PR (cursor=`src/beta` on main), run the sweep again **without making any changes** inside `src/gamma` or `src/delta`. Both should be processed as candidates but `src/gamma` should not be skipped (no prior commit for it). Confirm the skip count for previously-processed dirs with no new changes.

The cleaner test: reset state to re-process `src/alpha` without touching its files.

```bash
# Reset cursor so src/alpha is re-evaluated
cd ../AIDevToolsDemo
git checkout main && git pull origin main

# Manually set cursor to null to restart from beginning
# Edit claude-chain-sweep/add-dir-readme/state.json:
#   { "cursor": null, "lastRunDate": "..." }
git add claude-chain-sweep/add-dir-readme/state.json
git commit -m "Reset add-dir-readme cursor for skip detection test"

ai-dev-tools-kit sweep run \
  --task claude-chain-sweep/add-dir-readme \
  --repo . \
  --dry-run
```

**Expected behaviour**:
- `src/alpha` is evaluated first. It already has a `README.md` committed and no files changed since the cursor commit → `canSkipDirectory` returns `true` → skipped.
- `src/beta` is evaluated next. Same situation → skipped.
- Dry-run stats show `skipped=2` (or equivalent), `tasks=0`.

**Verify** by reading the dry-run stdout for skip indicators. If `skipped=0` and the AI is re-processing already-handled dirs, `canSkipDirectory` is not working correctly.

Fix any failures. Commit fixes to AIDevTools.

---

## - [x] Phase 6: Recursive Pattern `src/**/*/`

**Skills used**: none
**Principles applied**: Created `add-dir-readme-recursive` chain with `filePattern: "src/**/*/"`, `scanLimit: 4`, `changeLimit: 1`. Dry-run returned "1 task(s), 0 skipped" — correct for `changeLimit: 1` with `src/alpha` first candidate. Verified recursive `**` expansion by running the existing `doubleStarExpandsRecursively` unit test, which passes and confirms `src/alpha/subdir` appears in enumeration alongside top-level dirs.

Create a second sweep chain that uses double-star recursion to walk directories at all nesting depths. The `src/alpha/subdir/` created in Phase 1 should appear in this enumeration.

### 6a — Create chain `add-dir-readme-recursive`

Files in `../AIDevToolsDemo/claude-chain-sweep/add-dir-readme-recursive/`:

**`spec.md`**: same as `add-dir-readme`.

**`config.yaml`**:
```yaml
filePattern: "src/**/*/"
scanLimit: 4
changeLimit: 1
```

### 6b — Dry-run to confirm recursive enumeration

```bash
cd ../AIDevToolsDemo
ai-dev-tools-kit sweep run \
  --task claude-chain-sweep/add-dir-readme-recursive \
  --repo . \
  --dry-run
```

**Expected behaviour**:
- Enumeration includes both top-level dirs (`src/alpha`, `src/beta`, ...) AND nested dirs (`src/alpha/subdir`).
- Sorted alphabetically: `src/alpha`, `src/alpha/subdir`, `src/beta`, `src/delta`, `src/gamma`.
- `src/a.txt`, `src/b.txt`, etc. do NOT appear.

**Verify** that `src/alpha/subdir` appears in the enumerated list. If it does not, `expandDirectories` is not recursing correctly for `**/*/`.

Fix any failures.

---

## - [x] Phase 7: Validation

**Skills used**: none
**Principles applied**: Ran each verification command in the table top-to-bottom. All 10 rows passed without fixes: dry-run confirmed dir-only enumeration with 2 skipped, git log confirmed alphabetical cursor progression (alpha→beta), `status`/`list` commands confirmed both sweep chains visible, unit test `doubleStarExpandsRecursively` confirmed nested dir enumeration, and SweepClaudeChainSource.swift:162 confirms `"Directory"` label is used in directory mode.

All of the following should be provable by running CLI commands from `../AIDevToolsDemo`:

| Feature | Verification command |
|---|---|
| Directory mode activated by trailing `/` | `config.yaml` has `filePattern: "src/*/"` and enumeration shows dirs not files |
| Flat files excluded from `src/*/` enumeration | Dry-run output contains `src/alpha` but not `src/a.txt` |
| Dirs enumerated in alphabetical order | First two candidates are `src/alpha`, `src/beta` |
| Task instructions say `Directory:` not `File:` | PR diff commit message or AI output references "Directory: src/alpha" |
| First batch creates PR with correct cursor | `state.json` cursor=`src/alpha`, PR opened |
| Cursor advances on second batch | After merge, cursor=`src/beta`, new PR |
| Skip detection skips unchanged dirs | Dry-run after reset shows `skipped=2` when dirs unmodified |
| Recursive `src/**/*/` includes nested dirs | `src/alpha/subdir` appears in enumeration |
| `status` command shows `add-dir-readme [sweep]` | `claude-chain status --repo-path ../AIDevToolsDemo` |
| `list` command shows both sweep chains | `claude-chain list --repo-path ../AIDevToolsDemo` |

Run through this table top-to-bottom. For each row that fails, apply a targeted fix with a descriptive commit, then re-verify.

End state: All rows pass with no manual intervention beyond running the CLI commands shown.

---

## - [x] Phase 8: Enforce Coding Standards

**Skills used**: `ai-dev-tools-enforce`
**Principles applied**: Removed AI-changelog comment from `GitClient.swift`; documented two intentional `try?` suppressions with explanatory comments; removed dead `if !options.dryRun` guard (always false after the early-return at line 92); replaced `filePattern ?? ""` silent fallback with a `guard`+throw and a new `SweepConfigError.missingFilePattern` with an actionable `LocalizedError` message.

After all fixes are applied across Phases 2–7, run the enforce skill against every file changed in AIDevTools during this plan.

Use the `ai-dev-tools-enforce` skill to:
1. Check architecture layer violations
2. Check code quality (force unwraps, raw strings, fallback values)
3. Check build quality (warnings, dead code, TODO/FIXME left behind)
4. Check file/type organization

Apply any corrections as a final clean-up commit: `chore: enforce standards on directory sweep e2e fixes`.
