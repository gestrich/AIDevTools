- When asked to verify eval results, read eval output, inspect artifacts, debug eval failures, or run evals, use the `ai-dev-tools-debug` skill first to load file paths and CLI commands.
- Skills live in `.agents/skills/` (Codex convention). `.claude/skills` is a symlink to `.agents/skills` so Claude discovers them too. New skills should be created in `.agents/skills/`.
- Keep lists sorted alphabetically when the order doesn't need to be logical (e.g., Package.swift targets, CLI command definitions, enum cases, imports).


### Skills to use

* swift-architecture: For any architecture or planning activities
