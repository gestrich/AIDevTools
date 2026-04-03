- When asked to verify eval results, read eval output, inspect artifacts, debug eval failures, or run evals, use the `ai-dev-tools-debug` skill first to load file paths and CLI commands.
- When the user describes a problem with the app, reports an error, or posts a screenshot showing an issue, use the `ai-dev-tools-debug` skill first to check logs before investigating code.
- Skills live in `.agents/skills/` (Codex convention). `.claude/skills` is a symlink to `.agents/skills` so Claude discovers them too. New skills should be created in `.agents/skills/`.
- Keep lists sorted alphabetically when the order doesn't need to be logical (e.g., Package.swift targets, CLI command definitions, enum cases, imports).


### Skills to use

* ai-dev-tools-debug: When the user describes a problem, reports an error, or posts a screenshot showing an issue
* logging: When reading logs, debugging via logs, or adding logging to new features
* pr-radar-add-rule: When adding new PRRadar code review rules
* pr-radar-debug: When debugging PRRadar behavior, inspecting pipeline output, or reproducing Mac app issues via CLI
* pr-radar-todo: When adding items to the PRRadar TODO list
* pr-radar-verify-work: When verifying PRRadar changes against the test repo
* swift-architecture: For any architecture or planning activities
