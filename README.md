# AIDevTools

AIDevTools is a macOS app and CLI toolkit for AI-assisted software development. It provides tools for evaluating AI coding agents, chatting with AI, planning and executing implementations architecturally, reviewing pull requests with rules-based analysis, and automating task chains with GitHub Actions.

## Mac App and CLI

AIDevTools ships as two interfaces backed by the same shared logic:

- **Mac App** — A native macOS application with a multi-tab interface, live output panels, and persistent history.
- **CLI (`ai-dev-tools-kit`)** — A command-line tool covering the same features, suitable for scripting and CI pipelines.

A second dedicated CLI, **`claude-chain`**, handles the ClaudeChain automated PR workflow.

## Features

### AI Chat

Two chat modes in a toggleable panel:

- **API Chat** — Talk to Claude directly via the Anthropic API with streaming responses and persistent conversation history.
- **Claude Code Chat** — Interact with the Claude Code CLI with session history, slash command autocomplete, image attachments, and message queuing.

### AI Evaluator

Run structured test cases against AI providers (Claude Code and Codex) to measure how well they handle coding tasks. Define assertions — required text, file changes, command traces, and rubric-based quality checks — then inspect results with per-case grading details and saved artifacts. Compare providers side-by-side across suites of test cases.

See [AI Evaluator documentation](docs/features/evals/evals.md) for details.

### AI Planning

Describe what you want to build in plain language and get a phased implementation plan. Execute phases one at a time with live progress tracking, completion checklists, and elapsed time monitoring. Plans are stored per repository and can be created, resumed, and managed from the app or CLI.

See [AI Planning documentation](docs/features/plans/plans.md) for details.

### Architecture Planner

Walk a feature description through a 10-step AI pipeline that extracts requirements, maps them to your codebase's architecture, scores guideline conformance, simulates execution decisions, and produces a report with followup items. Guidelines are seeded from architecture docs and bundled Swift architecture guidelines, and can be customized per repository.

See [Architecture Planner guide](docs/guides/architecture-planner.md) for details.

### ClaudeChain

Automate sequences of Claude Code tasks across GitHub pull requests. Define tasks in a `spec.md` file; ClaudeChain picks the next unchecked task, creates a branch, runs Claude Code to complete it, and opens a PR. When the PR is merged, the chain advances to the next task automatically. Supports both sequential spec-based chains and batch sweep processing over files.

See [ClaudeChain documentation](docs/features/claude-chain/claude-chain.md) for setup and usage.

### PRRadar

Review pull requests against configurable markdown rule files. The pipeline fetches the PR diff, uses AI to generate focus areas, evaluates changed code against matching rules (via regex or AI), and posts inline review comments on GitHub. Integrates with GitHub Actions for automated CI review.

See [PRRadar documentation](docs/features/pr-radar/pr-radar.md) for setup and usage.

### Skill Browser

Browse, preview, and manage Claude Code skills (`.agents/skills/`) available in the current repository.

See [Skill Browser documentation](docs/features/skills/skills.md) for details.

### Sweep

Apply a Claude Code task across a set of files in a repository, collecting the changes into a single PR. Useful for large-scale refactors or consistent transformations across many files.

### Worktrees

Create and manage git worktrees — additional working directories for the same repository checked out to different branches. Used internally by ClaudeChain and Sweep to run tasks in isolation without disturbing the main working tree.

See [Worktrees documentation](docs/features/worktrees/worktrees.md) for details.
