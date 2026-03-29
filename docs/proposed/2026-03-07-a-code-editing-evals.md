> **2026-03-29 Obsolescence Evaluation:** Phases 1-9 completed successfully. Core edit-mode eval functionality implemented including EvalMode enum, file content/diff assertions, autonomous permissions, and tool call logging. Phase 10 (end-to-end validation) remains incomplete and sample edit-mode cases from Phase 5 are missing.

## Relevant Skills

- **`ai-dev-tools-debug`**: Use this skill before any validation, debugging, or artifact inspection steps. It contains file paths, CLI commands, and artifact layout for the eval system. Update this skill with new debugging tips discovered during subsequent phases.

## Background

The current eval system supports a two-layer grading approach (modeled after [OpenAI's eval-skills pattern](https://developers.openai.com/blog/eval-skills)):

- **Layer 1 — Deterministic checks**: `mustInclude`/`mustNotInclude` on response text, `traceCommandContains`/`traceCommandOrder` on the command trace, `filesExist`/`filesNotExist` on repo state
- **Layer 2 — Rubric grading**: Model-assisted evaluation with `overall_pass`, `score`, and per-check results

The system already captures JSONL event traces, streams output, and tracks tool events. However, the prompt currently forces the provider to only return structured JSON output ("Return JSON that matches the provided output schema"). The provider never edits files, so `git diff` is always empty.

To support real coding evals, we need the prompt to tell the provider to **edit files AND return structured output** describing what it did. Structured output stays — we grade both the explanation and the actual file changes. This extends the grading with file-content and diff assertions while keeping everything else intact.

### What already works

- Structured output with `result` schema (provider describes what it did)
- `mustInclude`/`mustNotInclude` on response text
- `traceCommandContains`, `traceCommandNotContains`, `traceCommandOrder` on command trace
- `maxCommands`, `maxRepeatedCommands` for detecting thrashing/loops
- `filesExist`, `filesNotExist` for repo state
- Rubric grading with model-assisted scoring
- Git diff capture before reset (just added)
- JSONL trace artifact storage

### What's missing

- A `mode` field so the prompt tells the provider to edit files (not just answer)
- File content assertions (`fileContains`, `fileNotContains`)
- Diff content assertions (`diffContains`, `diffNotContains`)
- Plumbing to pass the captured diff into the grading pipeline
- Rubric grading for edit mode needs to run **before** git reset so the grading AI can read the actual codebase state (not just the diff) for full context

## Phases

## - [x] Phase 1: Add `mode` field to EvalCase

Add an optional `mode` field to `EvalCase` to distinguish eval styles:

- `"structured"` (default, current behavior): Provider returns structured JSON only, no file edits expected
- `"edit"`: Provider edits files in the repo AND returns structured output describing what it did

Both modes keep structured output. The difference is only in the prompt and which grading assertions are meaningful.

```jsonl
{"id": "add-flag-edit", "mode": "edit", "task": "Add a boolean feature flag called 'newChecklistDesign'...", "must_include": ["newChecklistDesign"], "deterministic": {"fileContains": {"FlagKit/.../AppFlags.swift": ["newChecklistDesign"]}, "diffContains": ["newChecklistDesign"]}}
```

**Files to modify:**
- `EvalService/Models/EvalCase.swift` — add `public let mode: EvalMode?` with a `Codable` enum (`structured`, `edit`) defaulting to `structured`

## - [x] Phase 2: Update PromptBuilder for edit mode

**Principles applied**: Edit mode uses a single prompt path (ignores `input` field) since edit tasks are open-ended discovery, not snippet transformations. Used switch on `EvalMode` for clarity.

When `mode == .edit`, the prompt should instruct the provider to make file changes AND return structured output. The structured output schema stays the same (`result` string) — the provider uses it to describe what it did.

Current prompt (structured-only):
> "Task: {task}\n\nReturn JSON that matches the provided output schema."

Edit mode prompt:
> "Task: {task}\n\nMake the requested changes directly by editing files in the repository. After making changes, return JSON that matches the provided output schema with a summary of what you changed."

**Files to modify:**
- `EvalService/PromptBuilder.swift` — in `buildPrimaryPrompt`, branch on `evalCase.mode`:
  - `.structured` / `nil`: current behavior
  - `.edit`: include instruction to edit files, still request structured output summary

## - [x] Phase 3: Add file content and diff grading assertions

**Principles applied**: Added `diff` parameter to existing `grade()` with default `nil` — no backward compat shims needed since all new fields are optional and callers compile as-is.

Extend `DeterministicChecks` with assertions that check actual file state and diff:

- `fileContains: [String: [String]]?` — map of relative file path to strings that must appear in that file
- `fileNotContains: [String: [String]]?` — map of relative file path to strings that must NOT appear
- `diffContains: [String]?` — strings that must appear in the git diff
- `diffNotContains: [String]?` — strings that must NOT appear in the diff

**Files to modify:**
- `EvalService/Models/EvalCase.swift` — add new fields to `DeterministicChecks`
- `EvalService/DeterministicGrader.swift` — implement the new assertion checks:
  - `fileContains`/`fileNotContains`: read the file at `repoRoot + path` and check substrings
  - `diffContains`/`diffNotContains`: check against a diff string parameter

## - [x] Phase 4: Run all grading before git reset for edit mode

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Moved `captureGitDiff` to `GitClient` (SDK layer, stateless CLI wrapper) and extracted `RubricEvaluator` (SDK layer, eliminates rubric grading duplication between use cases). Use cases remain thin orchestrators.

> **Note:** Backward compatibility is not needed — callers can be updated directly.

Currently the flow is:
1. `RunCaseUseCase.run()` — runs provider, does deterministic + rubric grading
2. Back in `RunEvalsUseCase` — capture diff, then git reset

For edit mode, grading (both deterministic file checks and rubric) must happen **before** git reset, while the code changes are still on disk. The rubric grading AI should be told that the code changes are live in the codebase so it can read any files it needs for context — not just the diff. This is important because the grader may need to see surrounding code, conventions, file structure, etc. to properly evaluate the changes.

New flow for edit mode:
1. Provider runs and edits files
2. Capture git diff
3. Run deterministic file/diff assertions (new `gradeFileChanges`)
4. Run rubric grading — the rubric prompt template gets a new instruction: "The code changes from this task are currently applied to the repository at `{{repo_root}}`. You can read any files to evaluate the changes." The `{{result}}` variable still contains the provider's structured summary.
5. Merge all errors into `CaseResult`
6. Git reset

This means rubric grading for edit-mode cases needs to move from `RunCaseUseCase` into `RunEvalsUseCase` (or be callable from there). For structured-mode cases, nothing changes.

**Files to modify:**
- `EvalService/DeterministicGrader.swift` — add `gradeFileChanges(case:diff:repoRoot:)` for file/diff assertions
- `EvalFeature/RunEvalsUseCase.swift` — for edit-mode cases, after diff capture:
  1. Call `gradeFileChanges()` and merge errors
  2. Call rubric grading (if configured) before git reset
  3. Then reset
- `EvalService/PromptBuilder.swift` — add `{{repo_root}}` to rubric template rendering (already supported). Update rubric prompt conventions to note that for edit-mode cases, the grader has access to the live codebase.
- `EvalFeature/RunCaseUseCase.swift` — for edit-mode cases, skip rubric grading (it will be handled by `RunEvalsUseCase` after diff capture instead)

## - [x] Phase 5: Write sample edit-mode eval cases

**Principles applied**: Mirrored existing structured case but with `mode: "edit"`, exercising all three grading layers (response text, deterministic file/diff, rubric with live codebase access)

Create edit-mode cases in the feature-flags suite. These should mirror the existing structured cases but expect actual file edits:

```jsonl
{"id": "add-bool-flag-edit", "mode": "edit", "task": "Add a new boolean feature flag called 'newChecklistDesign' for a checklist redesign that is in development. Add the FlagKitKey and Flag entry in AppFlags.swift.", "must_include": ["newChecklistDesign"], "deterministic": {"filesExist": ["FlagKit/Sources/FlagKit/ClientFlags/AppFlags.swift"], "fileContains": {"FlagKit/Sources/FlagKit/ClientFlags/AppFlags.swift": ["newChecklistDesign", "featurePhase: .development"]}, "diffContains": ["newChecklistDesign", ".development"], "diffNotContains": [".release"]}, "rubric": {"prompt": "Evaluate the code changes made to add a 'newChecklistDesign' feature flag. The changes are currently applied to the repository at {{repo_root}} — read the relevant files to assess quality.\n\nThe provider's summary: {{result}}\n\nCheck:\n1. FlagKitKey uses Self(\"newChecklistDesign\") not FlagKitKey(avoidMemberCheck:)\n2. Flag entry is placed at the end of the flags dictionary, before the closing bracket\n3. featurePhase is .development with correct default values for a dev feature", "require_overall_pass": true, "min_score": 2, "required_check_ids": ["key-convention", "placement", "phase-defaults"]}}
```

This case grades on three layers:
1. **Response text**: `mustInclude` checks the structured output summary mentions the flag
2. **Deterministic file/diff checks**: verify the right strings appear in the right files and diff
3. **Rubric grading**: an AI reads the actual codebase to evaluate code quality, conventions, and placement — not limited to just the diff

**Files to modify:**
- `~/Desktop/ai-dev-tools/sample-evals/cases/feature-flags.jsonl` — add edit-mode cases

## - [x] Phase 6: Fix `--repo` flag and validate grading pipeline

**Principles applied**: Fixed two bugs blocking edit-mode evals from running against real repos. Validated all three grading layers work end-to-end.

The first run revealed that `repoRoot` was always set to `cwd` instead of the `--repo` path, so the provider ran in the wrong directory. A second bug was a URL trailing-slash mismatch in repo config lookup.

**Bugs fixed:**
- `RunEvalsCommand.swift`: When `--repo` is used, set `repoRoot` to the repo URL (not cwd)
- `RepositoryConfigurationStore+CLI.swift`: Compare `.standardized.path` instead of `.standardized` to avoid trailing-slash mismatch between `URL(fileURLWithPath:)` (adds `/`) and stored config URLs (no `/`)

**Validation results:**
- Provider now runs in the correct repo (`cwd: /path/to/sample-app`)
- Structured output returned correctly
- `fileContains`/`diffContains` deterministic assertions work (correctly detected missing edits)
- Rubric grading ran against live codebase (correctly scored 0 when changes weren't applied)
- Artifacts stored in `artifacts/claude/` and `artifacts/raw/`
- All three grading layers (response text, deterministic file/diff, rubric) working together

**How to reproduce:**
```bash
cd /Users/bill/Developer/personal/AIDevTools/AIDevToolsKit
swift run ai-dev-tools-kit run-evals --repo /path/to/sample-app --case-id add-bool-flag-edit --provider claude --debug
```

**Remaining issue:** The provider's Edit/Write/Bash tool calls were all rejected with "This command requires approval" since there is no interactive human to approve. The provider hallucinated a successful edit in its structured output, but the grading pipeline correctly caught that no files were actually changed.

## - [x] Phase 7: Enable autonomous file edits for the Claude provider

**Skills used**: `ai-dev-tools-debug`
**Principles applied**: Only edit-mode cases get `--dangerously-skip-permissions`; structured cases and rubric grading always run without it. Threaded `evalMode` through `RunConfiguration` with `.structured` default so existing callers (RubricEvaluator, CodexAdapter) are unaffected.

The Claude adapter (`EvalSDK/ClaudeCLI.swift`) currently launches `claude -p` without any permission flags. When `mode == .edit`, the provider needs permission to write files autonomously.

**Research needed:**
1. Check what Claude Code CLI flags exist for non-interactive permissions (e.g. `--dangerously-skip-permissions`, `--allowedTools`, or environment variables)
2. Determine the safest approach — full skip vs. scoped tool allowlist (Edit, Write, Bash)
3. Consider whether the eval system should always allow writes, or only for `mode == .edit` cases

**Files modified:**
- `EvalSDK/ClaudeCLI.swift` — added `@Flag("--dangerously-skip-permissions")` to the `Claude` CLI struct
- `EvalSDK/ProviderAdapterProtocol.swift` — added `evalMode: EvalMode` to `RunConfiguration` (defaults to `.structured`)
- `EvalSDK/ClaudeAdapter.swift` — sets `dangerouslySkipPermissions: true` when `configuration.evalMode == .edit`
- `EvalFeature/RunCaseUseCase.swift` — passes `evalCase.mode` through to `RunConfiguration`

## - [x] Phase 8: Add tool call outcome logging for Claude

**Skills used**: `ai-dev-tools-debug`
**Principles applied**: Correlated tool_use/tool_result events via id, classified errors as rejected vs errored by scanning output text, filtered out StructuredOutput tool results from counts. Added hallucination detection for empty diffs with non-empty provider response.

Currently, when provider tool calls fail (permissions denied, errors), the only way to see this is by reading the raw JSONL stdout artifact. Add structured logging so failures are visible in the eval output.

**Improvements:**
1. Parse tool call results from the Claude stream events and count successes/failures by correlating `tool_use` (assistant events with `id`) with `tool_result` (user events with `tool_use_id` and `is_error`)
2. Log a warning when Edit/Write/Bash calls are rejected (e.g. `"⚠ 12 tool calls rejected (permissions)"`)
3. Add a `ToolCallSummary` struct with counts: `{attempted: N, succeeded: N, rejected: N, errored: N}`
4. Add `toolCallSummary` to both `ProviderResult` and `CaseResult`
5. For edit-mode cases, warn if diff is empty but the provider claimed to make changes (hallucination detection)
6. Classify errors as "rejected" (output contains "requires approval" or "not allowed") vs generic "errored"

**Files to modify:**
- `EvalSDK/OutputParsing/ClaudeStreamModels.swift` — add `id` to `ClaudeContentBlock` (for tool_use correlation), add `isError` to `ClaudeUserContentBlock`
- `EvalService/Models/ProviderTypes.swift` — add `ToolCallSummary` struct, add `toolCallSummary` to `ProviderResult`
- `EvalSDK/OutputParsing/ClaudeOutputParser.swift` — parse user events (tool results), correlate with tool calls via id/tool_use_id, populate `ToolEvent.output`, classify results, build `ToolCallSummary`
- `EvalService/Models/CaseResult.swift` — add optional `toolCallSummary` field
- `EvalFeature/RunCaseUseCase.swift` — pass `toolCallSummary` from `ProviderResult` through to `CaseResult`
- `EvalFeature/RunEvalsUseCase.swift` — add warning error when tool calls are rejected; add hallucination detection for edit-mode cases with empty diff

## - [x] Phase 9: Add tool call outcome logging for Codex

**Skills used**: `ai-dev-tools-debug`
**Principles applied**: Matched Claude's ToolCallSummary pattern but simplified — Codex uses self-contained `item.completed` events with `exit_code` instead of paired request/response. No "rejected" concept since Codex has no permission system. Filtered to `item.completed` events only to avoid double-counting `item.started`.

**Skills to read:** `ai-dev-tools-debug`

Extend the same `ToolCallSummary` tracking to the Codex provider. Codex uses a different event format — `command_execution` items with `exit_code` instead of Claude's paired `tool_use`/`tool_result` events.

**Codex event model:**
- Tool calls appear as `item.completed` events with `item.type == "command_execution"`
- Each item has `exit_code` (0 = success, non-zero = error) and `aggregated_output`
- No separate request/response pairing needed — each completed item is self-contained
- Codex doesn't have a "rejected" concept (no permission system like Claude's)

**Improvements:**
1. Count tool call outcomes from `command_execution` items using `exit_code`
2. Build `ToolCallSummary` in `CodexOutputParser` (attempted = total command executions, succeeded = exit code 0, errored = exit code != 0, rejected = 0 always)
3. Pass `toolCallSummary` through `CodexAdapter` → `ProviderResult` (already has the field from Phase 8)
4. Add tests mirroring the Claude parser tests

**Files to modify:**
- `EvalSDK/OutputParsing/CodexOutputParser.swift` — track `ToolCallSummary` during parsing, count succeeded/errored based on `exit_code`
- `EvalSDK/OutputParsing/CodexOutputParser.swift` — add `toolCallSummary` to `Output` struct and pass through `buildResult`
- `Tests/EvalSDKTests/CodexOutputParserTests.swift` — add tests for tool call summary with successful, failed, and mixed command executions

## - [ ] Phase 10: End-to-end validation with working edits

**Skills to read:** `ai-dev-tools-debug`

After Phases 8-9, re-run the full validation:
1. `ai-dev-tools-kit run-evals --repo /path/to/sample-app --case-id add-bool-flag-edit --provider claude`
2. Verify provider actually edits files (diff is captured and non-empty)
3. Verify `fileContains` / `diffContains` assertions pass
4. Verify rubric grading reads the live codebase and passes
5. Verify git reset cleans up the edits after grading
6. Verify diff shows in Mac app output view
7. Run existing structured-mode cases to confirm no regressions
8. Check tool call summary in the output for both Claude and Codex providers
9. Run a structured-mode case with `--provider codex` and verify tool call summary appears

**After completion:** Update `ai-dev-tools-debug` skill with final debugging tips and any new artifact types or CLI flags added during phases 8-9.
