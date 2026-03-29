> **2026-03-29 Obsolescence Evaluation:** Completed. The skill invocation detection fix was implemented with InvocationMethod enum distinguishing between .explicit (Claude Skill tool use), .discovered (Claude accidental file read), and .inferred (Codex heuristic). Provider-specific logic in ClaudeProvider+EvalCapable and CodexProvider+EvalCapable handles the different detection paths described in the plan.

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-debug` | Debugging guide for evals — file paths, CLI commands, artifact paths, grading pipeline |

## Background

Skills in Claude and Codex are defined as markdown files (typically in `.claude/skills/` or `.agents/skills/`) with YAML front matter. The front matter contains fields like `description` and trigger conditions that tell the AI when and why to use the skill. This front matter is exposed to the AI's main context window — it's what drives whether the AI proactively invokes the skill for a given task.

The problem is that "invocation" can happen accidentally. When an AI is researching a codebase — doing greps, reading directories, exploring file trees — it will naturally encounter skill files because they live inside the repo. If the AI does a `grep` looking for information about a topic and the skill file happens to match, the AI reads the skill content. But this is NOT the skill being invoked. The AI stumbled upon it during research, not because the front matter description triggered the AI to proactively use it.

Genuine skill invocation means the AI recognized from the front matter (in its context) that the skill is relevant to the current task and chose to activate it on its own. The log events and traces for genuine invocation likely look different from the AI simply finding and reading the skill file during a codebase search. The exact difference in how this appears may vary between Claude and Codex, since they handle skill discovery and invocation differently.

Currently, the eval grading may not distinguish between these two scenarios. If that's the case, an eval case that asserts "skill was invoked" could pass even when the AI only accidentally found the skill file, which defeats the purpose of testing whether the skill's front matter is good enough to trigger proactive use.

### Test Case

This repo has an existing skill and eval case that's ideal for testing: the `what-time-is-it` skill (`.agents/skills/what-time-is-it/SKILL.md`). It has clear front matter:

```yaml
name: what-time-is-it
description: Returns the current time. Use when the user asks what time it is or wants to know the current time.
```

With a corresponding eval case (`demo-cases/cases/what-time-is-it.jsonl`) that asserts `skillMustBeInvoked: "what-time-is-it"`. The plan uses this skill directly — progressively weakening its front matter to test at what point invocation detection breaks.

---

## Phases

## - [x] Phase 1: Research Skill Invocation Mechanics

**Skills used**: `ai-dev-tools-debug`
**Principles applied**: Traced the full grading pipeline, ran Codex evals with `RUST_LOG=trace` for debug output, researched Codex API layers, inspected raw JSONL traces across multiple runs

**Skills to read**: `ai-dev-tools-debug`

### Findings

#### Claude — Clean protocol-level distinction

Claude has a dedicated `Skill` tool. The trace signals are unambiguous:

- **Genuine invocation**: `tool_use` event with `name: "Skill"`, `input.skill: "<skill-name>"`. The `ClaudeOutputParser` extracts `ToolEvent(name: "Skill", skillName: "map-layer")`.
- **Accidental file read**: `tool_use` event with `name: "Read"`, `input.file_path: "<path>"`. Produces `ToolEvent(name: "Read", filePath: "...")`.
- The tool name alone (`"Skill"` vs `"Read"`) is the definitive signal.

#### Codex — No protocol-level distinction

Codex has NO dedicated skill tool. All actions appear as `command_execution` events in the JSONL stream:

- **Genuine invocation**: `{"type":"item.completed","item":{"type":"command_execution","command":"sed ... .agents/skills/what-time-is-it/SKILL.md"}}`
- **Accidental file read**: Identical format — same `command_execution` with the skill path in the command string.

Ran Codex 4 times with strong front matter. All 4 passed. In 3 of 4, Codex read the skill file as its very first command (strong signal of catalog-driven activation). In 1 of 4 (with `RUST_LOG=trace`), Codex emitted an `agent_message` commentary ("I'm using the `what-time-is-it` skill...") before the file read, but this was not consistent across runs and is unreliable as a heuristic.

#### Codex internal signals (not exposed to us)

Codex internally tracks skill invocations but doesn't expose them:

- `codex.skill.injected` OTel metric with `invocation_type: Explicit` vs `Implicit` — exactly the distinction we want, but goes to OpenAI telemetry only
- `detect_skill_doc_read()` internal function — matches `cat`/`sed`/`head` commands against SKILL.md paths (same heuristic we use)
- App-server v2 WebSocket protocol has `skillMetadata` on some events, but switching from `codex exec` to WebSocket would be a significant rewrite
- The OpenAI Responses API (upstream model API) has zero concept of skills — skills are entirely a Codex-layer construct

#### Current grading bug

The `skillWasInvoked()` function in `DeterministicGrader.swift` (line 260) has three detection paths:

1. **Path 1** — `ToolEvent.skillName == skillName`: Only matches Claude `Skill` tool calls. **Reliable.**
2. **Path 2** — `ToolEvent.filePath` matches skill path convention: Matches any Claude `Read` of a skill file, including accidental reads. **False-positive risk.**
3. **Path 3** — Trace commands contain skill path strings: Matches any Codex `cat`/`sed` of a skill file, including accidental reads. **False-positive risk.**

Path 2 was added for nested skills (parent skill "ios-26" reading child "merge-insurance-policy.md" via `Read`), but also matches accidental reads.

For Claude, the fix is straightforward: Path 1 alone is the reliable signal for genuine invocation. Paths 2 and 3 should only be used for Codex (where they're the only option).

For Codex, there is no fix possible with current data — the heuristic is the best we can do.

## - [x] Phase 2: Fix Claude skill invocation detection

**Skills to read**: `ai-dev-tools-debug`

Update `skillWasInvoked()` in `DeterministicGrader.swift` to distinguish between Claude and Codex detection paths:

- **Claude**: Only use Path 1 (`ToolEvent.skillName`). This is the `Skill` tool call — unambiguous genuine invocation. Do NOT fall through to Path 2 (filePath) or Path 3 (trace commands) for Claude. An accidental `Read` of a skill file should not count.
- **Codex**: Continue using Path 2 and Path 3 (file path and trace command matching) since that's the only data available.

The grader already receives `providerCapabilities` — add a way to determine the provider so the detection logic can branch. Alternatively, check whether `toolEvents` contains any events with `name == "Skill"` or `name == "Read"` (Claude-specific tool names) to infer the provider.

## - [x] Phase 3: Add skill invocation indicator to CLI/UI output

**Skills to read**: `ai-dev-tools-debug`

When a `skillMustBeInvoked` or `skillMustNotBeInvoked` assertion is evaluated during grading, add a visible indicator in the CLI and Mac app output showing:

- Which skill was checked
- Whether it was detected as invoked or not
- **For Codex**: Include a disclaimer noting that Codex lacks a dedicated skill tool, so invocation detection is based on file read heuristics and cannot distinguish genuine invocation from accidental discovery

This helps users understand the confidence level of skill invocation assertions per provider.

## - [x] Phase 4: Update tests

**Skills to read**: `swift-testing`

Update `DeterministicGraderTests.swift`:

- Add test: Claude `Read` of a skill file does NOT pass `skillMustBeInvoked` (accidental read)
- Add test: Claude `Skill` tool call DOES pass `skillMustBeInvoked` (genuine invocation)
- Add test: Codex trace command with skill path still passes `skillMustBeInvoked` (heuristic, only option)
- Verify existing nested skill path tests still work for Codex path

## - [x] Phase 5: Validation

**Skills to read**: `ai-dev-tools-debug`, `swift-testing`

- Run `swift test` — all tests pass
- Run `swift build` — no compiler errors
- Run `what-time-is-it` eval for both Claude and Codex — both still pass with strong front matter
- Verify the CLI output includes the new skill invocation indicator and Codex disclaimer
