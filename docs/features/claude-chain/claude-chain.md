# ClaudeChain

ClaudeChain automates sequences of Claude Code tasks across GitHub pull requests. You define a list of tasks in a `spec.md` file; ClaudeChain picks the next unchecked task, creates a branch, runs Claude Code to complete it, and opens a PR. When the PR is merged, the workflow triggers again to process the next task.

```
spec.md tasks          PRs                        Result
─────────────          ───                        ──────
- [ ] Task 1    →    PR #1    → merge →    - [x] Task 1
- [ ] Task 2    →    PR #2    → merge →    - [x] Task 2
- [ ] Task 3    →    PR #3    → merge →    - [x] Task 3
```

## Project Structure

Each ClaudeChain project lives under a `claude-chain/` directory in your repository:

```
claude-chain/
  <project-name>/
    spec.md            # Task list (required)
    configuration.yml  # Project config (optional)
    pr-template.md     # PR body template (optional)
    pre-action.sh      # Script run before Claude Code (optional)
    post-action.sh     # Script run after Claude Code (optional)
```

The `spec.md` file describes the project and lists tasks as markdown checkboxes:

```markdown
# My Refactor Project

Describe the goal of this project and any context Claude needs.

## Tasks

- [x] First task (already done)
- [ ] Second task (next to run)
- [ ] Third task
```

ClaudeChain finds the first unchecked task (`- [ ]`) and runs it. When the PR for that task is merged, the task is marked complete (`- [x]`) and the chain continues.

## Mac App

The Mac app provides a visual interface for monitoring and managing chains:

- View all projects and their current task status
- Trigger runs and watch live AI output
- Browse chains from local and remote (GitHub API) sources
- Monitor open PRs per project

## CLI

The `claude-chain` CLI provides management commands for local use:

```bash
# Set up a new repository interactively
claude-chain setup <repo-path>

# List projects and their task status
claude-chain list

# Show status of projects
claude-chain status

# View project statistics
claude-chain statistics
```

The setup wizard (`claude-chain setup`) guides you through creating the workflow file, configuring GitHub settings, and creating your first project.

## Feature Guides

| Guide | Description |
|-------|-------------|
| [How It Works](claude-chain/how-it-works.md) | PR chain, task identification, automatic continuation |
| [Setup](claude-chain/setup.md) | Workflow file, secrets, permissions, action reference |
| [Projects](claude-chain/projects.md) | spec.md format, configuration.yml, pre/post scripts, PR templates |
| [Notifications](claude-chain/notifications.md) | Slack, PR summaries, statistics reports |
| [Best Practices](claude-chain/best-practices.md) | When to use ClaudeChain, prompting tips, team expectations |
| [Claude Prompt Tips](claude-chain/claude-prompt-tips.md) | Tooling, critical tool enforcement, working directory |
| [Troubleshooting](claude-chain/troubleshooting.md) | Common issues and solutions |
