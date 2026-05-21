---
name: claude-chain
description: Manages ClaudeChain automated PR chains. Use when working with claude-chain projects, listing open chain PRs, rebasing chain branches, triggering chain workflow runs, checking chain capacity, fetching workflow logs, creating new chains, or updating/editing an open chain PR locally.
user-invocable: true
disable-model-invocation: true
---

# Claude Chain Management

ClaudeChain is a GitHub Actions workflow in `gestrich/AIDevTools` (a Swift port of the original `gestrich/claude-chain` Python tool) that automates PR creation. You define tasks in a `spec.md`, and ClaudeChain creates a fixed number of PRs at a time — when one is merged, it automatically creates the next to maintain capacity.

**Script paths**: All `scripts/` references below are relative to this skill's directory. Resolve the full path based on where this SKILL.md file is located before executing.

## Chain Project Location

All chain projects live under `claude-chain/` at the repo root. Each project is a subdirectory:

```
claude-chain/
├── my-project/
│   ├── spec.md              # Required: task list with - [ ] checkboxes
│   ├── configuration.yml    # Optional: assignee, baseBranch, labels
│   ├── pr-template.md       # Optional: PR body template (uses {{TASK_DESCRIPTION}})
│   ├── pre-action.sh        # Optional: runs before Claude
│   └── post-action.sh       # Optional: runs after Claude
```

**Note:** Some chain projects may only exist on non-main branches. Check the base branch in `configuration.yml` or use `gh` to find them.

## Key Identifiers

- **PR label**: `claudechain` — all chain PRs carry this label
- **Branch pattern**: `claude-chain-{project-name}-{hash}`
- **Workflow**: `Claude Chain` (file: `claude-chain.yml`)
- **Repo**: `gestrich/AIDevTools`
- **Concurrency group**: `claude-chain` (only one chain runs at a time)
- **Concurrency limitation**: GitHub allows at most 1 running + 1 pending workflow per concurrency group. If multiple chain PRs are merged in quick succession, only the first (running) and last (pending) triggers survive — intermediate triggers are cancelled. After bulk-merging, use `chain-capacity.sh` to backfill lost slots.

## Common Operations

### List Open Chain PRs
**Always use `chain-status.sh`** — it uses GraphQL pagination to return all open chain PRs across all base branches. Do NOT use `gh pr list` directly, as it defaults to 30 results and will silently miss PRs (especially those on non-main branches).
```bash
scripts/chain-status.sh              # all open chain PRs
scripts/chain-status.sh <project>    # filter by project name
```

### Rebase All Open Chain PRs
Checks out each open chain branch, rebases onto its base branch, and force-pushes. **Always confirm with the user before force-pushing.**
```bash
scripts/chain-rebase.sh
```

### Trigger Next Chain Item
Dispatches the workflow to process the next unchecked task in a project's spec.md:
```bash
scripts/chain-trigger.sh <project_name> [base_branch]
```
The `base_branch` defaults to `main` if not specified. Read `configuration.yml` for the project to determine the correct base branch.

### Check & Fill Capacity (Single Project)
Checks how many tasks remain unchecked in the spec vs how many PRs are already open for that project, then triggers workflow runs to fill remaining capacity:
```bash
scripts/chain-capacity.sh <project_name> [base_branch] [max_open_prs] [wait_last]
```
`max_open_prs` defaults to the value in `configuration.yml`, or 1 if not set. Pass a non-empty value for `wait_last` to also wait for the final dispatched run to complete (required when calling from a loop).

### Fill Capacity Across Multiple Projects
Discovers all projects matching a prefix, then fills each to its `maxOpenPRs` capacity serially — waiting for all runs per project to complete before moving to the next:
```bash
scripts/chain-fill.sh <project_prefix> [base_branch]
```
Use this when multiple related chain projects need topping up (e.g., after bulk-merging PRs). Reads `maxOpenPRs` from each project's `configuration.yml`. Skips projects already at capacity or fully complete.

### Fetch Workflow Logs
```bash
scripts/chain-logs.sh [run_id]
```
Without `run_id`, lists recent workflow runs. With `run_id`, fetches logs for that specific run.

### Inspecting a GitHub Actions URL
The user may share a GitHub Actions URL like:
```
https://github.com/gestrich/AIDevTools/actions/runs/23354803587
```
This is a **Claude Chain workflow run**. Extract the run ID from the URL (the number at the end) and fetch its logs:
```bash
scripts/chain-logs.sh 23354803587
```
Look for key information in the logs: which project and task it ran, whether it succeeded or failed, and any error messages. Summarize what happened for the user.

### Create a New Chain
Interactive — asks for project name, base branch, assignee, labels, and task list:
```bash
scripts/chain-create.sh <project_name>
```
Or create manually — see [reference.md](reference.md) for the file templates.

### Update a Chain PR

When the user wants to make changes to an open chain PR locally, follow this procedure:

**Step 1: Check for unsaved local work.** Before checking out the PR branch, check the working tree status:
```bash
git status --short
git log --oneline origin/main..HEAD  # check for unpushed commits (use the current branch's remote if not on main)
```
Report to the user what would be lost:
- **Uncommitted changes**: list the modified/untracked files briefly
- **Unpushed commits**: list the commit subjects briefly
- If HEAD is detached and not pushed to any remote branch, those commits would be orphaned

Ask the user to confirm before proceeding. Do not check out until they confirm.

**Step 2: Check out the PR in detached HEAD.** Do not create a local branch — detached HEAD is preferred:
```bash
git fetch origin <pr_branch_name>
git checkout FETCH_HEAD
```
Get the PR branch name from `gh pr view <number> --repo gestrich/AIDevTools --json headRefName --jq .headRefName`.

**Step 3: Make the requested changes.** Apply whatever edits the user asked for.

**Step 4: Confirm and push.** Show the user the diff of changes and ask them to confirm before pushing:
```bash
git diff  # show what changed
```
Once confirmed, commit and push back to the PR branch:
```bash
git push origin HEAD:<pr_branch_name>
```

### Fetch PR Summary Comment
When ClaudeChain creates a PR, it posts a `## ClaudeChain Summary` comment (from `devops_jepp`) explaining what was done and including cost breakdown. **Always read this comment first** when reviewing or understanding a chain PR — it provides essential context about the changes.
```bash
# Summary for a specific PR
scripts/chain-summary.sh <pr_number>

# Summaries for all open chain PRs
scripts/chain-summary.sh all

# Summaries for a specific project's open PRs
scripts/chain-summary.sh all <project_name>
```

## Checking Multiple Chain Projects

When the user asks to check many chain projects (e.g., "check the file space chains"), use the `chain-check.sh` script:
```bash
scripts/chain-check.sh <project_prefix>
```
This outputs TSV data with all projects matching the prefix, their open PRs, and task progress.

### Output Format

Use the TSV output from `chain-check.sh` to produce two parts:

#### Part 1: Summary Table

One row per project — **no individual PRs**. Shows progress and open PR count.

| Project | Progress | Open PRs |
|---------|----------|----------|
| **model-cli-parity** | 3/12 | 1 |
| **fix-models-apps-layer** | 5/8 | 1 |
| ~~old-project~~ | ~~4/4~~ | |

- **Project**: Use the full project name from the PROJECT column. Bold active projects. ~~Strikethrough~~ completed ones (done == total).
- **Progress**: `done/total` from the DONE and TOTAL columns
- **Open PRs**: Count of open PRs for that project. Empty for completed projects.
- **Ordering**: Active projects first (sorted by most remaining tasks), then completed projects at the bottom.

After the table, add a one-line summary: `**N/M tasks complete across P projects. X open PRs.**`

#### Part 2: Open PRs Table

A single table listing all open PRs across all projects. The Project column repeats for projects with multiple PRs. Skip projects with no open PRs.

| Project | PR | Title | Age | Approved | Pending Review | Build |
|---------|----|-------|-----|----------|----------------|-------|
| model-cli-parity | #142 | Add anthropic-api provider parity... | 2d | gestrich | | ✅ |
| model-cli-parity | #145 | Wire codex provider into CLI... | 1d | | gestrich | ⏳ CI |
| fix-models-apps-layer | #133 | Move provider list to Apps layer... | 8d | gestrich | | ❌ Merge conflicts |

**Column rules:**
- **Project**: Full project name from the PROJECT column. Repeated for each PR in the same project.
- **Title**: Shortened title from the script output
- **Age**: Days the PR has been open (from DAYS_OPEN column)
- **Approved**: Reviewers who have approved (from APPROVED column)
- **Pending Review**: Reviewers who have been requested but not yet reviewed (from PENDING_REVIEW column)
- **Build**: Convert BUILD column: `PASS` → ✅, `CONFLICTING` → ❌ Merge conflicts, `FAIL:names` → ❌ names, `PENDING:names` → ⏳ names

## PR Summary Output Format (Single PR or Small Set)

When the user asks for PR summaries for specific PRs (not a bulk project check), include reviewers and build state alongside the ClaudeChain summary. Present results as a markdown table:

| PR | Summary | Reviewers | Build |
|----|---------|-----------|-------|
| #142 | Adds anthropic-api provider parity in CLI | gestrich | ✅ |

**Build column rules:**
- ✅ — all checks pass (treat `skipping` and `not run` as passing)
- ⏳ — one or more checks are `pending` or `in_progress`. List the pending check names after the symbol, e.g. `⏳ ForeFlight Tests`
- ❌ — one or more checks have `fail` status. List the failed check names after the symbol, e.g. `❌ SwiftLint, ForeFlight Tests`
- ❌ Merge conflicts — when the PR's `mergeable` state is `CONFLICTING`, show `❌ Merge conflicts` regardless of check status

**Ignored checks:** Filter out these checks entirely — they are not meaningful for chain PRs:
- Any check in `skipping` or `not run` state

**How to gather the data** (run these in parallel for each PR):
1. `chain-summary.sh` — get the ClaudeChain summary comment (condense to one line for the table)
2. `gh pr view <number> --repo gestrich/AIDevTools --json reviews,mergeable --jq '{reviewers: ([.reviews[] | select(.state == "APPROVED") | .author.login] | unique | join(", ")), mergeable: .mergeable}'` — get approving reviewers and merge conflict state
3. `gh pr checks <number> --repo gestrich/AIDevTools` — get build check status. Filter out `skipping` entries, `Process` jobs, and `Deploy` jobs; report `fail` and `pending` ones.

## Understanding Chain State

To understand the current state of a chain:

1. **Read `spec.md`** on the base branch — `- [x]` tasks are done, `- [ ]` are pending
2. **List open PRs** for the project — these are in-flight work
3. **Read the ClaudeChain Summary comment** on each PR — explains what was done and why
4. **Check approvals** on each open PR — who has reviewed/approved
5. **Check CI status** on each open PR — look for failing checks or errors
6. **Remaining capacity** = (unchecked tasks) - (open PRs for that project)

```bash
# Get open PRs — always use chain-status.sh (paginated, all branches)
scripts/chain-status.sh

# Get approvals for a specific PR
gh pr view <pr_number> --repo gestrich/AIDevTools --json reviews \
  --jq '.reviews[] | select(.state == "APPROVED") | .author.login'

# Get failing checks for a specific PR
gh pr checks <pr_number> --repo gestrich/AIDevTools --fail-only
```

A chain project may exist on a branch other than `main`. Check `configuration.yml` for `baseBranch`, or look at the `baseRefName` on open PRs.

## Merging Multiple Chain PRs

GitHub's concurrency group allows at most 1 running + 1 pending workflow. When merging multiple chain PRs in quick succession, each merge triggers a workflow run, but intermediate pending runs get cancelled by newer ones. Only the first (already running) and last (newest pending) survive.

**After bulk-merging**, always run `chain-fill.sh` (multiple projects) or `chain-capacity.sh` (single project) to backfill the lost trigger slots:
```bash
scripts/chain-fill.sh <project_prefix>              # all matching projects
scripts/chain-capacity.sh <project_name> [base_branch]  # single project
```

**To avoid the issue entirely**, merge PRs one at a time with a gap (wait for each chain workflow run to complete before merging the next). This is slower but ensures every trigger fires.

## Detailed Reference

For file templates, configuration options, workflow details, and advanced usage, see [reference.md](reference.md).
