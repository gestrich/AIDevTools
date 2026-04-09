# Troubleshooting

This guide covers common issues and solutions when using ClaudeChain.

## Quick Reference

| Symptom | Likely Cause | Quick Fix |
|---------|--------------|-----------|
| First task not starting | Spec PR not merged | Merge PR with spec.md changes |
| Merge doesn't trigger | Wrong base branch or closed without merge | Verify merged to correct branch |
| Spec not found | Not pushed to base branch | `git push origin main` |
| Base branch mismatch | Config baseBranch differs from merge target | Update configuration.yml |
| Can't create PRs | Permissions not enabled | Settings → Actions → Allow PRs |
| App not installed | Claude Code GitHub App missing | `/install-github-app` |
| Rate limit | Too many API calls | Wait 1 hour |
| Orphaned PRs | Task description changed | Close old PR |
| PR already open | One PR per project limit | Merge existing PR |

## First Task Not Starting

**Symptom:** You added a project but no PR was created.

**Option 1: Merge a Spec PR (Recommended)**

1. Create a PR that adds your spec.md file
2. Merge the PR

ClaudeChain automatically detects the spec.md change and creates the first task PR.

**Option 2: Manual trigger**

1. Go to **Actions** → **ClaudeChain** → **Run workflow**
2. Enter your project name (e.g., `my-refactor`)
3. Enter the base branch (e.g., `main`)
4. Click **Run workflow**

## PR Merge Doesn't Trigger Next Task

**Check 1: Verify It Was Merged**

The PR must be **merged**, not just closed. Check the PR page—it should say "merged" with a purple icon.

**Check 2: Check Changed Files**

The PR must change files under `claude-chain/`. If the PR doesn't include any changes to spec.md or other files in that directory, the workflow won't trigger.

**Check 3: Verify Base Branch Match**

If your project uses a non-main base branch (configured in `configuration.yml`), ensure the PR was merged into that branch.

**Check 4: Check Workflow Logs**

1. Go to **Actions** → **ClaudeChain**
2. Find the run triggered by your merge
3. Look for skip reasons or errors:
   - "Base branch mismatch" — PR merged to wrong branch
   - "PR was closed without merging"
   - "No tasks remaining"

**Check 5: Verify Tasks Remain**

If all tasks are complete (`- [x]`), there's nothing left to do. Add more tasks or start a new project.

## Spec File Not Found

**Error:**
```
Error: spec.md not found in branch 'main'
Required file:
  - claude-chain/my-project/spec.md
```

ClaudeChain fetches spec files from your base branch via the GitHub API. They must be committed and pushed:

```bash
git add claude-chain/my-project/spec.md
git commit -m "Add spec.md"
git push origin main
```

## Workflow Permissions Issues

**Error:**
```
Error: GitHub Actions is not permitted to create pull requests
```

1. Go to **Settings** → **Actions** → **General**
2. Scroll to **Workflow permissions**
3. Check **"Allow GitHub Actions to create and approve pull requests"**
4. Click **Save**

## Claude Code GitHub App Not Installed

**Error:**
```
Error: Claude Code GitHub App is not installed
```

1. Open Claude Code in your terminal
2. Execute:
   ```
   /install-github-app
   ```
3. Follow the prompts to install the app

## API Rate Limits

**Error:**
```
Error: GitHub API rate limit exceeded
```

GitHub has rate limits on API calls. If exceeded:
1. **Wait** — Rate limits reset hourly
2. **Reduce concurrency** — Run fewer projects simultaneously
3. **Space out merges** — Don't merge many PRs at once

## Orphaned PR Warnings

**Warning:**
```
⚠️  Warning: Found 2 orphaned PR(s):
  - PR #123 (claude-chain-auth-39b1209d) - task hash no longer matches any task
```

Orphaned PRs occur when you changed a task description or deleted a task that had an open PR.

**Resolution:**
1. Review each orphaned PR
2. Close it
3. ClaudeChain creates a new PR for the current task

See [Projects Guide - Modifying Tasks](./projects.md#modifying-tasks) for how to avoid orphaned PRs.

## PR Already Open for Project

**Message:**
```
Project already has an open PR. Skipping PR creation.
```

ClaudeChain enforces one open PR per project at a time by default. Review and merge the open PR to allow the next task to proceed.

To allow multiple concurrent PRs, set `maxOpenPRs` in your project's `configuration.yml`.

## Workflow Runs But No PR Created

**Check 1: Review Workflow Output**

1. Go to **Actions** → find the workflow run
2. Expand the ClaudeChain step
3. Look for outputs:
   - `skipped: true` — Check `skip_reason`
   - `all_steps_done: true` — All tasks complete
   - `has_capacity: false` — No capacity for new PR

**Check 2: Verify Unchecked Tasks Exist**

Ensure `spec.md` has at least one unchecked task (`- [ ]`).

**Check 3: Check for Errors**

Look for error messages in the workflow logs for API failures, permission errors, or file not found.

## Base Branch Mismatch

**Symptom:** Workflow skips with "base branch mismatch" message.

**Cause:** The PR was merged into a branch that doesn't match the project's configured `baseBranch`.

Check your project's `configuration.yml` and ensure PRs target the correct branch:

```yaml
baseBranch: develop  # PRs must merge into 'develop'
```

## Getting More Help

If you can't resolve an issue:

1. **Check workflow logs** — Detailed error messages are in Actions
2. **Search existing issues** — [github.com/gestrich/claude-chain/issues](https://github.com/gestrich/claude-chain/issues)
3. **Open a new issue** — Include the error message, workflow file (sanitize secrets), steps to reproduce, and relevant workflow run logs
