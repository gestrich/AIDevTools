- When asked to verify eval results, read eval output, inspect artifacts, debug eval failures, or run evals, use the `ai-dev-tools-debug` skill first to load file paths and CLI commands.
- When the user describes a problem with the app, reports an error, or posts a screenshot showing an issue, use the `ai-dev-tools-debug` skill first to check logs before investigating code.
- Skills live in `.agents/skills/` (Codex convention). `.claude/skills` is a symlink to `.agents/skills` so Claude discovers them too. New skills should be created in `.agents/skills/`.
- Keep lists sorted alphabetically when the order doesn't need to be logical (e.g., Package.swift targets, CLI command definitions, enum cases, imports).
- `AIDevTools.xcodeproj` is generated from `project.yml` by XcodeGen and is gitignored. To regenerate, run `scripts/generate-xcodeproj.sh` (not bare `xcodegen generate` — the wrapper also writes `xcshareddata/WorkspaceSettings.xcsettings` with `IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded=false`, which XcodeGen has no native option for; without it Xcode prompts "Autocreate Schemes" on every open because of the many transitive Swift Package targets). `DEVELOPMENT_TEAM` is read from `Local.xcconfig` (gitignored; copy `Local.xcconfig.example`) — never hardcode the team in `project.yml`.


### Skills to use

* ai-dev-tools-architecture: When reviewing or fixing Swift code for 4-layer architecture violations (layer placement, dependencies, orchestration, etc.)
* ai-dev-tools-build-quality: When cleaning up compiler warnings, TODO/FIXME comments, dead code, or debug artifacts
* ai-dev-tools-code-organization: When reviewing or fixing Swift file and type organization
* ai-dev-tools-code-quality: When reviewing or fixing code quality issues (force unwraps, raw strings, fallback values, duplicated logic, etc.)
* ai-dev-tools-composition-root: When adding new shared services, wiring providers or credentials, reviewing how dependency construction works, or any question about how the Mac app or CLI commands get their services
* ai-dev-tools-debug: When the user describes a problem, reports an error, posts a screenshot showing an issue, or is debugging PRRadar behavior (pipeline output, rule evaluation, Mac app issues)
* ai-dev-tools-enforce: After making code changes, when asked to enforce standards, apply architecture guidelines, analyze for violations, or review what would need to change. Also use as a verification step at the end of every plan — after the final phase completes, run enforce on all files changed during the plan before considering the work done.
* ai-dev-tools-logging: When reading logs, debugging via logs, or adding logging to new features
* ai-dev-tools-pr-radar-add-rule: When adding new PRRadar code review rules
* ai-dev-tools-pr-radar-todo: When adding items to the PRRadar TODO list
* ai-dev-tools-swift-testing: When writing or reviewing Swift test files
* ai-dev-tools-ui-tests: When running UI tests, capturing app screenshots, writing new screenshot tests, extracting images from .xcresult bundles, or using the interactive test runner
* swift-architecture: For any architecture or planning activities
