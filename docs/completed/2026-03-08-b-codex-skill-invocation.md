> **2026-03-29 Obsolescence Evaluation:** Obsolete. Codex skill invocation detection was already comprehensively implemented in the completed plan "2026-03-08-b-skill-invocation-detection.md" which added provider-agnostic skill detection, reference file reading checks, and support for both Claude (tool calls) and Codex (shell command trace analysis).

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-debug` | Debugging guide for the eval system — CLI commands, artifact paths, and troubleshooting |

## Background

Codex is not invoking the `ai-dev-tools-joke` skill during evals. Claude passes this same eval reliably. We need to understand whether Codex can invoke skills at all, and if not, what options we have.

Initial research shows Codex fundamentally lacks a `Skill` tool — it only executes shell commands. However, the earlier sample-app `feature-flags` eval passed for Codex because it read the skill file via `sed` and the trace fallback detection (checking for `.claude/skills/<name>/` in commands) matched. This means Codex _can_ pass skill assertions if it happens to `cat`/`sed`/`read` the skill file, but it cannot use the `Skill` tool directly.

## Phases

## - [ ] Phase 1: Confirm Codex lacks Skill tool support

**Skills to read**: `ai-dev-tools-debug`

- Review `CodexAdapter.swift` — confirm no skill-related arguments are passed
- Review `CodexOutputParser.swift` — confirm `skillName` is never populated on `ToolEvent`
- Review `CodexStreamModels.swift` — confirm no skill event types exist
- Compare against `ClaudeOutputParser.swift` which explicitly extracts `skillName` from `Skill` tool use blocks
- Document the gap: Codex uses `command_execution` events only; Claude has `tool_use`/`tool_result` with skill detection

## - [ ] Phase 2: Investigate Codex CLI capabilities

- Check if `codex exec` supports any skill or plugin system natively
- Check if there's a `--skill` or `--system-prompt` flag that could inject skill content
- Check if `--full-auto` mode has any bearing on tool availability
- Check if Codex has a `.claude/skills` equivalent or reads them automatically when run in a repo directory

## - [ ] Phase 3: Analyze the trace fallback detection path

- The grader has two detection paths for `skillMustBeInvoked`:
  1. `toolEvents.contains(where: { $0.skillName == skillName })` — requires explicit skill tool use
  2. `traceCommands.contains(where: { $0.contains(".claude/skills/\(skillName)/") })` — matches any command that touches the skill file
- Codex can only pass via path 2 (reading the file directly)
- Determine: is relying on trace fallback sufficient, or should we skip skill assertions for Codex?

## - [ ] Phase 4: Research whether Codex should skip skill assertions

- Currently `CodexAdapter` reports `supportsToolEventAssertions: true` — this is arguably wrong for skill-specific assertions
- Options:
  - A) Add a separate capability flag like `supportsSkillInvocation: Bool` and skip skill checks when false
  - B) Change `supportsToolEventAssertions` to false for Codex — but this would skip ALL trace assertions (commands, order, etc.) which Codex does support
  - C) Keep current behavior — Codex passes if it reads the skill file, fails if it doesn't
  - D) Inject skill content into the Codex system prompt so it has the information even without the Skill tool
- Evaluate tradeoffs of each approach

## - [ ] Phase 5: Check if Codex permissions affect file reading

- Does `--full-auto` grant read access to `.claude/skills/`?
- Does `--ephemeral` mode restrict file system access?
- Could Codex be failing because it can't read the skill file rather than choosing not to?
- Check the raw Codex stdout for the failed joke eval to see what it actually did

## - [ ] Phase 6: Validation

**Skills to read**: `ai-dev-tools-debug`

- Run the `ai-dev-tools-joke` eval for Codex and inspect the raw trace output
- Run the `what-time-is-it` eval for Codex and inspect the raw trace output
- Compare against the sample-app `feature-flags` Codex run (which passed via trace fallback)
- Document findings and decide on the right approach
