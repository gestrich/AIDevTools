- When asked to verify eval results, read eval output, inspect artifacts, debug eval failures, or run evals, use the `ai-dev-tools-debug` skill first to load file paths and CLI commands.
- When the user describes a problem with the app, reports an error, or posts a screenshot showing an issue, use the `ai-dev-tools-debug` skill first to check logs before investigating code.
- Skills live in `.agents/skills/` (Codex convention). `.claude/skills` is a symlink to `.agents/skills` so Claude discovers them too. New skills should be created in `.agents/skills/`.
- Keep lists sorted alphabetically when the order doesn't need to be logical (e.g., Package.swift targets, CLI command definitions, enum cases, imports).


### Skills to use

* ai-dev-tools-architecture: When reviewing or fixing Swift code for 4-layer architecture violations (layer placement, dependencies, orchestration, etc.)
* ai-dev-tools-build-quality: When cleaning up compiler warnings, TODO/FIXME comments, dead code, or debug artifacts
* ai-dev-tools-code-organization: When reviewing or fixing Swift file and type organization
* ai-dev-tools-code-quality: When reviewing or fixing code quality issues (force unwraps, raw strings, fallback values, duplicated logic, etc.)
* ai-dev-tools-debug: When the user describes a problem, reports an error, or posts a screenshot showing an issue
* ai-dev-tools-enforce: After making code changes, when asked to enforce standards, apply architecture guidelines, analyze for violations, or review what would need to change
* ai-dev-tools-logging: When reading logs, debugging via logs, or adding logging to new features
* ai-dev-tools-pr-radar-add-rule: When adding new PRRadar code review rules
* ai-dev-tools-pr-radar-debug: When debugging PRRadar behavior, inspecting pipeline output, or reproducing Mac app issues via CLI
* ai-dev-tools-pr-radar-todo: When adding items to the PRRadar TODO list
* ai-dev-tools-swift-testing: When writing or reviewing Swift test files
* swift-architecture: For any architecture or planning activities
