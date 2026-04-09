# Worktrees

The Worktrees feature provides a UI and CLI for managing git worktrees — additional working directories checked out from the same repository at different branches.

Available in the **Worktrees** tab of the Mac app and via `ai-dev-tools-kit worktree --help` in the CLI.

## What Are Git Worktrees?

A git worktree lets you check out multiple branches of a repository simultaneously in separate directories. This is useful when you need to work on one branch while keeping another checked out, or when running automated tasks (like ClaudeChain or Sweep) that operate in isolated copies of the repo to avoid disturbing your working tree.

## Features

**List worktrees** — See all active worktrees for the current repository, including their paths and branches.

**Add a worktree** — Create a new worktree at a specified destination path, checked out to an existing or new branch.

**Remove a worktree** — Clean up worktrees that are no longer needed.

## Integration with Other Features

Worktrees are used internally by [ClaudeChain](../claude-chain/claude-chain.md) when running in isolated mode — each task gets its own worktree so it can make changes without affecting the main checkout.
