## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-debug` | Debugging context for eval system — file paths, CLI commands, artifacts |
| `swift-testing` | Test style guide and conventions |
| `swift-app-architecture:swift-architecture` | 4-layer Swift app architecture (Apps, Features, Services, SDKs) |

## Background

The OpenAI [Eval Skills](https://developers.openai.com/blog/eval-skills/) blog post describes verifying whether a skill was actually invoked during an eval run by inspecting structured event traces. Our system currently has a `shouldTrigger` field on `EvalCase`, but it only validates that the case is properly configured (e.g., `shouldTrigger: true` requires `mustInclude` to be non-empty). It does **not** check whether the provider actually called the Skill tool at runtime.

We need to close this gap for both Claude and Codex providers so that evals can assert:
- **Positive**: "The provider invoked skill X" (the Skill tool was called with the expected skill name)
- **Negative**: "The provider did NOT invoke any skill" (no Skill tool call appeared in the trace)
- **Reference file reads**: "The provider read reference file Y adjacent to the skill" (progressive disclosure worked correctly)

### Trace analysis from real runs

We inspected actual raw trace output from the `add-bool-flag-structured` eval case run against both providers:

**Claude** (`artifacts/raw/claude/feature-flags.add-bool-flag-structured.stdout`):
- Tool names used: `Glob`, `Grep`, `Read`, `StructuredOutput`
- **Did NOT use the `Skill` tool** — went straight to file exploration
- No `skillHint` was set on the case, so nothing prompted Claude to use the Skill tool
- Claude never read `SKILL.md` — it found the code through direct Read/Grep
- When `skillHint: "explicit"` is set, the prompt prepends "Use the skill name exactly as specified in the task." which should trigger Skill tool usage — but we need to verify this with a real run

**Codex** (`artifacts/raw/codex/feature-flags.add-bool-flag-structured.stdout`):
- Explicitly read `SKILL.md` as its **first command**: `cat .claude/skills/feature-flags/SKILL.md`
- Skill read appears as `item.completed` with `type: "command_execution"`
- No reference files were read (skill has none)
- All tool activity appears as `command_execution` events — no separate skill event type

**Key insight**: Claude and Codex handle skill invocation fundamentally differently:
- **Claude with `skillHint`**: Expected to use the `Skill` tool (function call with `name: "Skill"`, `input.skill: "feature-flags"`)
- **Claude without `skillHint`**: May skip the Skill tool entirely and go straight to file exploration
- **Codex**: Always reads skill files via shell commands (`cat`, `sed`) — detectable through `command_execution` trace events

### Skills with reference files in `sample-app`

```
map-layer/          → SKILL.md + feature-layers.md, marker-layers.md, master-set-layers.md
localization/       → SKILL.md + target-strings.md, swift-package-strings.md
skill-authoring/    → SKILL.md + best-practices.md, examples.md
feature-flags/      → SKILL.md only (no reference files)
build-app/          → SKILL.md only
app-services/       → SKILL.md + service-resolver/ (subdirectory, not .md)
merge-insurance-policy/ → SKILL.md only
```

To test reference file detection, we should use a skill with reference files (e.g., `map-layer` or `localization`).

### Provider differences

Both providers expose skill invocation through their structured event streams, but in different ways:

- **Claude**: Uses the `Skill` tool via function calling. The tool call appears in streaming output as `{"type":"tool_use", "name":"Skill", "input":{"skill":"design-kit", ...}}`. The `ClaudeOutputParser` already extracts `ToolEvent` objects with `name: "Skill"` and `inputKeys`, but does **not** extract the `skill` input value. Reference file reads appear as `Read` tool calls with `input["file_path"]` pointing to files adjacent to `SKILL.md` — this value is also not currently extracted.
- **Codex**: Skills are `SKILL.md` files in the repo. When Codex activates a skill, it reads the file and executes commands the skill prescribes. Both skill reads and reference file reads appear as `command_execution` events (e.g., `cat .claude/skills/my-skill/SKILL.md`, `cat .claude/skills/my-skill/reference.md`). Our existing `traceCommandContains` already supports matching these patterns. Codex uses [progressive disclosure](https://developers.openai.com/codex/skills/) — it starts with skill metadata, loads `SKILL.md` on activation, and reads additional bundled files only as needed.

### The underlying gap

The core problem for Claude is the same across skill invocation and reference file detection: **we extract tool names and input keys, but not input values**. The `ClaudeOutputParser.extractToolEvents()` method (line 92-105) currently extracts:
- `name` (e.g., `"Skill"`, `"Read"`, `"Bash"`)
- `inputKeys` (e.g., `["skill", "args"]`, `["file_path"]`)
- `command` (only for `Bash` tool — extracts `input["command"]`)

To support both skill invocation and reference file detection, we need to generalize input value extraction beyond just the Bash tool's command field.

### Design approach

**Extend `ToolEvent` with two new optional fields:**
- `skillName: String?` — populated when `name == "Skill"`, extracted from `input["skill"]`
- `filePath: String?` — populated when `name == "Read"`, extracted from `input["file_path"]`

**New `DeterministicChecks` assertions:**
- `skillMustBeInvoked` / `skillMustNotBeInvoked` — checks `ToolEvent.skillName` (Claude) or trace commands (Codex)
- `referenceFileMustBeRead` / `referenceFileMustNotBeRead` — checks `ToolEvent.filePath` (Claude) or trace commands (Codex) for reads of files adjacent to the skill directory

**Codex** already works via `traceCommandContains` for both cases. The new assertions provide a higher-level, provider-agnostic API that handles the provider differences internally.

### Reference

- [Eval Skills blog post](https://developers.openai.com/blog/eval-skills/) — motivation and approach
- [Codex Agent Skills docs](https://developers.openai.com/codex/skills/) — progressive disclosure, bundled resources
- [Claude Code Skills docs](https://code.claude.com/docs/en/skills) — skill directory structure, reference files
- Existing `SkillScanner` ([SkillScanner.swift](AIDevToolsKit/Sources/SkillScannerSDK/SkillScanner.swift)) — already discovers reference files (any `.md` in skill subdirectory that isn't `SKILL.md`)

## Phases

## - [x] Phase 0: Run providers and inspect trace output for skill with reference files

**Skills used**: `ai-dev-tools-debug`
**Principles applied**: Created `map-layer.jsonl` eval case with `skill_hint: "explicit"`, ran both providers, inspected raw JSONL traces

### Findings

**Claude** (`artifacts/raw/claude/map-layer.add-feature-layer-structured.stdout`):
- Used the `Skill` tool: `{"skill": "map-layer"}` — `input["skill"]` contains the skill name
- Read 2 of 3 reference files via `Read` tool:
  - `/path/to/sample-app/.claude/skills/map-layer/feature-layers.md`
  - `/path/to/sample-app/.claude/skills/map-layer/marker-layers.md`
- Tool call sequence: `Skill` → `Read` → `Read` → `StructuredOutput`
- Extraction strategy confirmed: `input["skill"]` for Skill tool, `input["file_path"]` for Read tool

**Codex** (`artifacts/raw/codex/map-layer.add-feature-layer-structured.stdout`):
- Read `SKILL.md` as first command: `sed -n '1,220p' .claude/skills/map-layer/SKILL.md`
- Read 2 of 3 reference files via shell commands:
  - `sed -n '1,260p' .claude/skills/map-layer/feature-layers.md`
  - `sed -n '1,320p' .claude/skills/map-layer/marker-layers.md`
- All reads appear as `command_execution` events with the skill path in the command string
- Detection strategy confirmed: match `.claude/skills/map-layer/` in trace commands

**Architecture insight for Phase 3**: The grader currently receives `traceCommands: [String]` built from `toolEvents.compactMap(\.command)`. For Claude, `command` is only populated for Bash tool calls, so Skill/Read tool events don't appear in `traceCommands`. The grader's `grade()` method signature must be extended to also accept `toolEvents: [ToolEvent]` so it can check `skillName`/`filePath` directly for Claude, while continuing to use `traceCommands` for Codex.

## - [x] Phase 1: Extend ToolEvent to capture skill name and file path

**Skills used**: `ai-dev-tools-debug`
**Principles applied**: Added two optional fields with nil defaults to maintain backward compatibility with all existing call sites

**Skills to read**: `ai-dev-tools-debug`

Add optional fields to `ToolEvent` for tool input values we need to assert on:

- **File**: `Sources/EvalService/Models/ProviderTypes.swift`
- Add `public var skillName: String?` — the skill name from Skill tool input
- Add `public var filePath: String?` — the file path from Read tool input
- Update `init` to accept both parameters (default `nil`)

## - [x] Phase 2: Extract input values in ClaudeOutputParser

**Skills used**: `ai-dev-tools-debug`
**Principles applied**: Extended existing extraction pattern (matching Bash/command) to Skill/skill and Read/file_path; added constants to keep string literals centralized

**Skills to read**: `ai-dev-tools-debug`

Update `ClaudeOutputParser.extractToolEvents()` to populate the new fields:

- **File**: `Sources/EvalSDK/OutputParsing/ClaudeOutputParser.swift`
- When `block.name == "Skill"`, extract `input["skill"]?.stringValue` → `skillName`
- When `block.name == "Read"`, extract `input["file_path"]?.stringValue` → `filePath`
- The parser already has access to the full `input` dictionary (line 100-101); currently only extracts values for the Bash tool

## - [x] Phase 3: Add skill and reference file assertions to DeterministicGrader

**Skills used**: `ai-dev-tools-debug`
**Principles applied**: Provider-agnostic assertions that check toolEvents for Claude and traceCommands for Codex; gated behind supportsToolEventAssertions; default parameter preserves backward compat with all existing callers

**Skills to read**: `ai-dev-tools-debug`

Add new assertion logic in `DeterministicGrader`:

- **File**: `Sources/EvalService/DeterministicGrader.swift`
- **Signature change**: Add `toolEvents: [ToolEvent]` parameter to `grade()` (currently only has `traceCommands: [String]`). The grader needs the full `toolEvents` array because Claude's Skill/Read tool events don't appear in `traceCommands` (only Bash commands do).
- **Caller update**: `Sources/EvalFeature/RunCaseUseCase.swift` line 97-104 — pass `providerResult.toolEvents` to the new parameter
- **Skill invocation checks:**
  - `skillMustBeInvoked: String?` — verify the skill was activated
    - **Claude**: at least one `ToolEvent` has matching `skillName` (e.g., `"map-layer"`)
    - **Codex**: at least one trace command contains `.claude/skills/{skillName}/` (e.g., `.claude/skills/map-layer/SKILL.md`)
  - `skillMustNotBeInvoked: [String]?` — verify skills were NOT activated (check both `skillName` and trace commands)
- **Reference file read checks:**
  - `referenceFileMustBeRead: [String]?` — list of file path substrings that must appear
    - **Claude**: at least one `ToolEvent` has `filePath` containing the substring (e.g., `"feature-layers.md"` matches `/Users/bill/.../map-layer/feature-layers.md`)
    - **Codex**: at least one trace command contains the path substring (e.g., `"feature-layers.md"` matches `sed -n '1,260p' .claude/skills/map-layer/feature-layers.md`)
  - `referenceFileMustNotBeRead: [String]?` — file path substrings that must NOT appear
- Gate all checks behind `supportsToolEventAssertions` (already `true` for both providers)

## - [x] Phase 4: Update EvalCase and DeterministicChecks models

**Skills used**: `ai-dev-tools-debug`
**Principles applied**: Fields were already added in Phase 3; snake_case JSON decoding handled by existing `CaseLoader.convertFromSnakeCase` strategy; `toolEvents` already wired through from `RunCaseUseCase`

- **File**: `Sources/EvalService/Models/EvalCase.swift`
  - Add to `DeterministicChecks`:
    - `skillMustBeInvoked: String?`
    - `skillMustNotBeInvoked: [String]?`
    - `referenceFileMustBeRead: [String]?`
    - `referenceFileMustNotBeRead: [String]?`
  - Support JSON decoding with snake_case variants

## - [x] Phase 5: Unit tests

**Skills used**: `swift-testing`, `ai-dev-tools-debug`
**Principles applied**: Arrange-Act-Assert pattern with section comments; tested both Claude toolEvent and Codex traceCommand paths for each assertion type; verified capability gating and nil/missing input edge cases

**Skills to read**: `swift-testing`

**Grader tests** (`Tests/EvalServiceTests/DeterministicGraderTests.swift`):
- Skill invocation present → passes when `skillMustBeInvoked` matches `ToolEvent.skillName`
- Skill invocation absent → fails when `skillMustBeInvoked` is set but no matching event
- Skill invocation present → fails when `skillMustNotBeInvoked` matches
- Skill invocation absent → passes when `skillMustNotBeInvoked` is set and no match
- Reference file read present → passes when `referenceFileMustBeRead` matches `ToolEvent.filePath`
- Reference file read absent → fails when `referenceFileMustBeRead` is set but no matching event
- Reference file read present → fails when `referenceFileMustNotBeRead` matches
- Codex — skill command in trace → passes when `skillMustBeInvoked` is set
- Codex — reference file command in trace → passes when `referenceFileMustBeRead` is set

**Parser tests** (`Tests/EvalSDKTests/ClaudeOutputParserTests.swift`):
- Skill tool call extracts `skillName` correctly
- Read tool call extracts `filePath` correctly
- Non-Skill/Read tool calls have `skillName == nil` and `filePath == nil`
- Skill tool call with missing `skill` input → `skillName == nil`
- Read tool call with missing `file_path` input → `filePath == nil`

## - [x] Phase 6: Validation

**Skills used**: `ai-dev-tools-debug`, `swift-testing`
**Principles applied**: Verified positive and negative assertions for both providers end-to-end; confirmed parser extracts skillName/filePath from raw traces; added negative control case (`no-skill-simple`) to validate mustNotBeInvoked/mustNotBeRead paths

**Skills to read**: `swift-testing`, `ai-dev-tools-debug`

### Automated checks
- Run `swift test --skip EvalIntegrationTests` — all unit tests pass
- Run `swift build` — no compiler errors
- Verify existing `GradingValidationTests` still pass (no regressions in grading framework)

### End-to-end verification with real providers

Update the `map-layer.jsonl` eval case (created in Phase 0) to add the new deterministic assertions, then re-run both providers:

**Update eval case** (`~/Desktop/ai-dev-tools/sample-evals/cases/map-layer.jsonl`):
```json
{"id":"add-feature-layer-structured","skill_hint":"explicit","should_trigger":true,"task":"...","must_include":["MapMarkerLayer","activateInMapEngine","allMapMarkers"],"deterministic":{"skill_must_be_invoked":"map-layer","reference_file_must_be_read":["feature-layers.md","marker-layers.md"]}}
```

**Claude verification:**
```bash
swift run ai-dev-tools-kit run-evals --repo /path/to/sample-app --case-id add-feature-layer-structured --provider claude
cat ~/Desktop/ai-dev-tools/sample-app/artifacts/claude/map-layer.add-feature-layer-structured.json
```
- Confirm `skillMustBeInvoked: "map-layer"` passes (Claude used `Skill` tool with `input.skill = "map-layer"`)
- Confirm `referenceFileMustBeRead: ["feature-layers.md", "marker-layers.md"]` passes (Claude `Read` both files)

**Codex verification:**
```bash
swift run ai-dev-tools-kit run-evals --repo /path/to/sample-app --case-id add-feature-layer-structured --provider codex
cat ~/Desktop/ai-dev-tools/sample-app/artifacts/codex/map-layer.add-feature-layer-structured.json
```
- Confirm skill invocation detected via trace command matching (`sed ... .claude/skills/map-layer/SKILL.md`)
- Confirm reference file reads detected via trace command matching (`sed ... feature-layers.md`)

### Success criteria

1. **Skill invocation detection works for Claude**: When `skill_hint: "explicit"` is set and Claude uses the Skill tool, `skillMustBeInvoked` assertion passes. The graded result JSON shows the skill name that was invoked.
2. **Skill invocation detection works for Codex**: When Codex reads `SKILL.md` via a shell command, `skillMustBeInvoked` assertion passes by matching the skill path in trace commands.
3. **Reference file read detection works for Claude**: When Claude reads a reference file adjacent to `SKILL.md` (e.g., `feature-layers.md`), `referenceFileMustBeRead` assertion passes by matching `ToolEvent.filePath`.
4. **Reference file read detection works for Codex**: When Codex `cat`s or `sed`s a reference file, `referenceFileMustBeRead` assertion passes by matching the path in trace commands.
5. **Negative controls work**: `skillMustNotBeInvoked` and `referenceFileMustNotBeRead` correctly fail when the provider does invoke/read the forbidden skill/file.
6. **No regressions**: All existing unit tests and `GradingValidationTests` continue to pass.
