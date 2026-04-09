# Setup Guide

This guide walks you through the one-time setup to get ClaudeChain running in your repository. Once configured, ClaudeChain will automatically create a chain of PRs from your task list—one task at a time, each building on the last.

## Prerequisites

Before setting up ClaudeChain, you need:

1. **Anthropic API key** — Get one from [console.anthropic.com](https://console.anthropic.com)
2. **GitHub repository** — Where you want to run ClaudeChain
3. **Write access** — You need permission to add workflows and secrets

## Create the Workflow File

Create `.github/workflows/claudechain.yml` in your repository.

**Important:** Commit this workflow file to your default branch (usually `main`). GitHub Actions requires workflow files to exist on the default branch for manual triggers (`workflow_dispatch`) to appear in the Actions UI.

### Recommended Workflow

This format handles project detection and event routing automatically:

```yaml
name: ClaudeChain

on:
  workflow_dispatch:
    inputs:
      project_name:
        description: 'Project name (folder under claude-chain/)'
        required: true
        type: string
      base_branch:
        description: 'Base branch where spec file lives'
        required: true
        type: string
        default: 'main'
  pull_request:
    types: [closed]
    paths:
      - 'claude-chain/**'

concurrency:
  group: claude-chain
  cancel-in-progress: false

permissions:
  contents: write
  pull-requests: write
  actions: read

jobs:
  run-claudechain:
    runs-on: ubuntu-latest
    steps:
      - uses: gestrich/claude-chain@main
        with:
          anthropic_api_key: ${{ secrets.CLAUDE_CHAIN_ANTHROPIC_API_KEY }}
          github_token: ${{ github.token }}
          project_name: ${{ github.event.inputs.project_name || '' }}
          default_base_branch: ${{ github.event.inputs.base_branch || 'main' }}
          claude_allowed_tools: 'Read,Write,Edit,Bash(git add:*),Bash(git commit:*)'
          # slack_webhook_url: ${{ secrets.CLAUDE_CHAIN_SLACK_WEBHOOK_URL }}
```

**What this does:**
- `workflow_dispatch` — Allows manual triggering with project name and base branch inputs
- `pull_request: types: [closed]` — Triggers when PRs are merged (for auto-continuation)
- `paths: ['claude-chain/**']` — Only triggers when files under claude-chain/ change
- `project_name` — Used for manual triggers; auto-detected for PR events from changed spec.md files
- `default_base_branch` — The branch PRs will target; validated against project config if set
- `claude_allowed_tools` — Controls which tools Claude can use (see [Tool Permissions](./projects.md#tool-permissions))
- `concurrency` — Serializes workflow runs (see [Concurrency](#concurrency) below)

### Concurrency

The `concurrency` block serializes ClaudeChain runs. This matters when using `maxOpenPRs > 1`, which allows multiple PRs to be open and merge concurrently. Without serialization, two problems can occur:

**Duplicate PR creation.** When two PRs merge at nearly the same time, both trigger a workflow run. Both runs see the same next available task and race to create the same PR.

**Spec merge conflicts.** Each merge marks a task complete in `spec.md`. If two runs push spec updates simultaneously, one push will be rejected.

The concurrency group ensures runs execute one at a time. The second run waits for the first to finish, sees the updated task list, and picks the correct next task.

```yaml
concurrency:
  group: claude-chain
  cancel-in-progress: false
```

- `cancel-in-progress: false` ensures queued runs **wait** rather than being cancelled.
- The `group` name can be anything. Use the same group across all ClaudeChain workflows in the repo.

**Tip:** When using `maxOpenPRs > 1`, add blank lines between tasks in your `spec.md` so each task gets its own git diff hunk. This prevents merge conflicts when adjacent tasks are marked complete by different PRs.

## Configure GitHub Settings

### Add the Anthropic API Key Secret

1. Go to **Settings** → **Secrets and variables** → **Actions** → **Repository secrets**
2. Click **New repository secret**
3. Name: `CLAUDE_CHAIN_ANTHROPIC_API_KEY`
4. Value: Your API key from [console.anthropic.com](https://console.anthropic.com)
5. Click **Add secret**

### Enable PR Creation Permission

1. Go to **Settings** → **Actions** → **General**
2. Scroll to **Workflow permissions**
3. Check **"Allow GitHub Actions to create and approve pull requests"**
4. Click **Save**

### Install Claude Code GitHub App (Optional)

This step enables using `@claude` mentions on PRs for interactive code review.

In your local repository, run Claude Code and execute:

```
/install-github-app
```

Follow the prompts to install the app on your repository.

### Optional: Add Slack Webhook

For PR creation notifications:

1. Get a webhook URL from [api.slack.com/messaging/webhooks](https://api.slack.com/messaging/webhooks)
2. Add as secret: `SLACK_WEBHOOK_URL`
3. Uncomment the `slack_webhook_url` line in your workflow file

## Start ClaudeChain

Before running ClaudeChain, you need at least one project. See the [Projects Guide](./projects.md) for creating `spec.md` and `configuration.yml`.

### Option 1: Merge a Spec PR (Recommended)

1. Create a branch and add your project files:
   ```bash
   git checkout -b add-my-project-spec
   mkdir -p claude-chain/my-project
   # Create spec.md (see Projects Guide)
   git add claude-chain/my-project/
   git commit -m "Add ClaudeChain project: my-project"
   git push origin add-my-project-spec
   ```
2. Create a PR from your branch
3. Merge the PR

ClaudeChain detects the spec.md change and automatically creates the first task PR.

### Option 2: Manual Trigger

1. Push your project files directly to main
2. Go to **Actions** → **ClaudeChain** → **Run workflow**
3. Enter your project name (e.g., `my-project`)
4. Enter the base branch (e.g., `main`)
5. Click **Run workflow**

### Verify It's Working

After triggering:
1. Go to **Actions** and watch the workflow run (~2-5 minutes)
2. Check **Pull requests** for a new PR
3. The PR title will be "ClaudeChain: {task description}"
4. The PR will have the `claudechain` label

## Action Reference

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `anthropic_api_key` | Yes | — | Anthropic API key for Claude Code |
| `github_token` | Yes | `${{ github.token }}` | GitHub token for PR operations |
| `project_name` | No | — | Project folder name. Auto-detected from changed spec.md files or workflow_dispatch input |
| `claude_model` | No | `claude-sonnet-4-6` | Claude model to use |
| `claude_allowed_tools` | No | `Read,Write,Edit,Bash(git add:*),Bash(git commit:*)` | Tools Claude can use (can be overridden per-project) |
| `base_branch` | No | (inferred) | Base branch for PRs |
| `default_base_branch` | No | `main` | Default if not determined from event |
| `working_directory` | No | `.` | Working directory |
| `add_pr_summary` | No | `true` | Add AI-generated summary to PR |
| `slack_webhook_url` | No | — | Slack webhook for notifications |
| `pr_label` | No | `claudechain` | Label for ClaudeChain PRs |
| `pr_labels` | No | (empty) | Additional labels to apply to PRs (comma-separated) |

### Outputs

| Output | Description |
|--------|-------------|
| `skipped` | Whether execution was skipped |
| `skip_reason` | Reason for skipping |
| `project_name` | Detected/resolved project name |
| `base_branch` | Resolved base branch |
| `pr_number` | Number of created PR |
| `pr_url` | URL of created PR |
| `task_completed` | Task description that was completed |
| `has_capacity` | Whether project has capacity for a new PR |
| `all_tasks_done` | Whether all tasks are complete |

### Tool Permissions

ClaudeChain uses minimal permissions by default. Configure tools at the workflow level (`claude_allowed_tools` input) or per-project (`allowedTools` in `configuration.yml`).

**Default tools:**

| Tool | Purpose |
|------|---------|
| `Read` | Read spec.md and codebase files |
| `Write` | Create new files |
| `Edit` | Modify existing files |
| `Bash(git add:*)` | Stage changes (required by ClaudeChain) |
| `Bash(git commit:*)` | Commit changes (required by ClaudeChain) |

**Additional tools available:**

| Tool | Description |
|------|-------------|
| `Bash` | Full shell access (use with caution) |
| `Bash(command:*)` | Restricted to specific command (e.g., `Bash(npm test:*)`) |
| `Glob` | Find files by pattern |
| `Grep` | Search file contents |

**Enabling additional Bash access:**

If your tasks require running tests, builds, or other shell commands, add them explicitly:

```yaml
- uses: gestrich/claude-chain@main
  with:
    claude_allowed_tools: 'Read,Write,Edit,Bash'
```

Or configure per-project in `configuration.yml`:

```yaml
allowedTools: Read,Write,Edit,Bash(git add:*),Bash(git commit:*),Bash(npm test:*),Bash(npm run build:*)
```

See [Projects Guide](./projects.md#tool-permissions) for per-project configuration details.

## Next Steps

- [Projects Guide](./projects.md) — Create your first project with `spec.md`
- [Notifications Guide](./notifications.md) — Set up Slack notifications and statistics
- [Troubleshooting](./troubleshooting.md) — Common issues and solutions
