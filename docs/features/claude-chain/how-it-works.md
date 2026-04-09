# How ClaudeChain Works

This guide explains the core concepts behind ClaudeChain—the mental model that helps you understand everything else.

## What ClaudeChain Does

ClaudeChain automates incremental code changes by:

1. Reading a task list you define in a `spec.md` file
2. Creating a pull request for one task at a time
3. Automatically starting the next task when you merge a PR

It's designed for work that would otherwise sit on the backlog forever—migrations, refactoring, code cleanup, documentation—breaking it into manageable, reviewable PRs.

**Key characteristics:**
- One PR at a time per project
- Human review required for each change
- Automatic continuation when PRs are merged
- Small, focused changes that are easy to review

## The PR Chain

ClaudeChain creates a chain of PRs, one task at a time:

```
spec.md                    PRs                           spec.md (after)
──────────                 ───                           ───────────────
- [ ] Task 1    →    PR #1 (Task 1)    → merge →    - [x] Task 1
- [ ] Task 2    →    PR #2 (Task 2)    → merge →    - [x] Task 2
- [ ] Task 3    →    PR #3 (Task 3)    → merge →    - [x] Task 3
```

**Flow:**
1. You write tasks in `spec.md` using checkbox syntax (`- [ ]`)
2. ClaudeChain finds the first unchecked task
3. Claude Code implements the task and creates a PR
4. You review and merge the PR
5. The task is automatically marked complete (`- [x]`)
6. ClaudeChain creates the next PR
7. Process repeats until all tasks are done

**Why one at a time?** Each PR is independently reviewable. If Claude makes a mistake, you catch it early. Changes stay small and focused.

## Task Identification

ClaudeChain uses **hash-based task identification**. Each task is identified by an 8-character SHA-256 hash of its description, not its position in the file.

**Example:**
```markdown
- [ ] Add user authentication    → hash: 39b1209d
- [ ] Add input validation       → hash: a8f3c2d1
- [ ] Update error messages      → hash: f7c4d3e2
```

**Why this matters:**

✅ **Reordering is safe.** Move tasks around freely—the hash stays the same.

✅ **Inserting is safe.** Add new tasks anywhere—they get new hashes.

✅ **Deleting completed tasks is safe.** No open PRs reference them.

⚠️ **Changing descriptions creates new tasks.** If you edit a task's text while a PR is open, the PR becomes "orphaned" (see [Orphaned PRs](#orphaned-prs)).

**Hash generation:** Only the checkbox line content is hashed. Whitespace is normalized, so minor formatting changes don't affect the hash.

```markdown
- [ ] Add user authentication      ← This text is hashed

  Implementation details here...   ← This is NOT hashed (can be changed freely)
```

## Branch Naming

ClaudeChain branches follow a predictable pattern:

```
claude-chain-{project}-{task-hash}
```

**Examples:**
- `claude-chain-auth-refactor-39b1209d`
- `claude-chain-api-cleanup-a8f3c2d1`

**Components:**
- `claude-chain` — Fixed prefix identifying ClaudeChain branches
- `{project}` — Your project folder name (e.g., `auth-refactor`)
- `{task-hash}` — 8-character hash of the task description

**Why include the hash?** It creates a stable link between the branch/PR and the task, even if tasks are reordered in `spec.md`.

## What Runs Where

ClaudeChain involves two systems working together:

### GitHub Action (ClaudeChain)
Runs in GitHub Actions. Handles orchestration:
- Reads your `spec.md` to find the next task
- Checks reviewer capacity
- Creates the branch
- Generates the prompt for Claude Code
- Creates the PR after Claude Code finishes
- Posts AI-generated summaries
- Marks tasks complete when PRs merge

### Claude Code
Runs in GitHub Actions (via `anthropics/claude-code-action`). Does the actual work:
- Reads the codebase
- Implements the task according to your spec
- Makes code changes
- Commits to the branch

**Separation of concerns:** ClaudeChain manages the workflow; Claude Code implements the code changes.

## Automatic Continuation

When you merge a PR that changes files under `claude-chain/`, the next task automatically starts. Here's how:

### Requirements for Auto-Continuation

1. **PR changes claude-chain/ files** — Detected from changed spec.md files
2. **PR is merged** — Not just closed (closing without merging won't trigger)
3. **Base branch matches** — PR merge target matches project's configured `baseBranch`
4. **Tasks remain** — At least one unchecked task exists in `spec.md`

### The Flow

```
1. You merge PR #1
         ↓
2. GitHub fires `pull_request: types: [closed]` event
         ↓
3. ClaudeChain workflow runs (paths filter matches claude-chain/**)
         ↓
4. Checks: Was merged? Does base branch match config?
         ↓
5. If yes: Finds next task, creates PR #2
         ↓
6. You review and merge PR #2
         ↓
   (cycle repeats)
```

### Starting the First Task

Start your first task by either:

1. **Creating a PR that adds your spec.md file, then merging it** (recommended) — ClaudeChain automatically detects the new spec and creates the first task PR
2. **Manual trigger:** Actions → ClaudeChain → Run workflow → Enter project name and base branch

## Orphaned PRs

An **orphaned PR** is a pull request whose task no longer exists or has changed.

### When Orphaned PRs Occur

1. **Task description changed** — You edited the checkbox text while a PR was open
2. **Task deleted** — You removed a task that had an open PR

### Why It Happens

Since tasks are identified by hash, changing the description creates a *new* hash. The existing PR references the *old* hash, which no longer matches any task.

**Example:**
```markdown
# Before (PR open for this task)
- [ ] Add user authentication    ← hash: 39b1209d

# After (you changed the description)
- [ ] Add OAuth authentication   ← hash: a8f3c2d1 (NEW hash!)

# Result: PR with branch 'claude-chain-...-39b1209d' is orphaned
```

### Detection and Resolution

ClaudeChain detects orphaned PRs and warns you:

```
⚠️  Warning: Found 1 orphaned PR(s):
  - PR #123 (claude-chain-auth-39b1209d) - task hash 39b1209d no longer matches any task

To resolve:
  1. Review the PR and verify if it should be closed
  2. Close the orphaned PR
  3. ClaudeChain will automatically create a new PR for the current task
```

**To resolve:**
1. Review the orphaned PR (click the link in the warning)
2. Close it (the work is for an outdated task)
3. The next workflow run creates a new PR with the updated task

### Avoiding Orphaned PRs

- **Wait for PRs to merge** before changing task descriptions
- **Or accept the trade-off:** Close the old PR, get a new one with the updated task

## Summary

| Concept | Key Point |
|---------|-----------|
| **PR Chain** | One task → one PR → merge → next task |
| **Task Identification** | Hash of description, not position |
| **Branch Naming** | `claude-chain-{project}-{hash}` |
| **Auto-Continuation** | Triggered by spec.md changes + merge + base branch match |
| **Orphaned PRs** | Occur when task descriptions change |
