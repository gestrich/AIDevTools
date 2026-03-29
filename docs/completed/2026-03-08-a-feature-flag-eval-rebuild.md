> **2026-03-29 Obsolescence Evaluation:** Obsolete. Feature-flags evaluation suite was already built in the completed plan "2026-03-07-a-skill-eval-integration.md" which created 7 cases covering flag creation, Swift/ObjC querying, typed accessors, lifecycle cleanup, etc. This rebuild effort is no longer needed.

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-debug` | Debugging context for eval system — file paths, CLI commands, artifact locations |

## Background

The AIDevTools app has not been user-tested thoroughly. The existing feature-flags eval suite (8 cases) was built in a rush to demonstrate basics. Bill wants to rebuild the suite deliberately, one case at a time, so each case can be validated before moving on. Each case serves a dual purpose:

1. **Feature flag skill validation** — Confirms the AI provider gives correct answers about the feature flag system (adding flags, querying them, ObjC interop, lifecycle, etc.)
2. **AIDevTools eval feature validation** — Each case intentionally exercises a specific eval system capability so we can confirm that capability works correctly.

The eval cases file is at `~/Desktop/ai-dev-tools/sample-evals/cases/feature-flags.jsonl`. Artifacts land in `~/Desktop/ai-dev-tools/sample-app/artifacts/`.

## Phases

## - [x] Phase 1: Remove existing cases and artifacts

**Skills used**: `ai-dev-tools-debug`
**Principles applied**: Verified clean slate with `list-cases` CLI command after clearing cases and artifacts

**Skills to read**: `ai-dev-tools-debug`

- Delete all lines from `~/Desktop/ai-dev-tools/sample-evals/cases/feature-flags.jsonl` (empty the file, keep it)
- Delete all `feature-flags.*` files from `~/Desktop/ai-dev-tools/sample-evals/artifacts/claude/` and `~/Desktop/ai-dev-tools/sample-evals/artifacts/raw/`
- Verify with `list-cases --suite feature-flags` that no cases remain

**AIDevTools features validated**: Clean slate — confirms `list-cases` correctly reports an empty suite.

## - [ ] Phase 2: Structured case with must_include / must_not_include

**Skills to read**: `ai-dev-tools-debug`

Create case: **`add-bool-flag-structured`**

- **Task**: "Add a new boolean feature flag called 'newChecklistDesign' for a checklist redesign that is in development. Show the code changes needed in AppFlags.swift."
- **Mode**: `structured` (default, omitted)
- **Assertions**: `must_include` for key patterns (`FlagKitKey`, `Self("newChecklistDesign")`, `featurePhase: .development`), `must_not_include` for anti-patterns (`featurePhase: .release`)

**What this demonstrates**:
- *Feature flag skill*: Can the provider correctly produce the Swift code for adding a boolean flag with development phase?
- *AIDevTools feature*: **Basic structured-mode grading** — the simplest eval path. Tests that `must_include`/`must_not_include` substring matching works on the provider's text response. This is the foundation all other checks build on.

**Validation**: Run with `--provider both`, check the case result JSON for each provider for pass/fail and verify each `must_include` item is correctly matched.

## - [ ] Phase 3: Structured case with rubric grading

**Skills to read**: `ai-dev-tools-debug`

Create case: **`flag-lifecycle-cleanup`**

- **Task**: "What should I do when adding a new feature flag to ensure it gets cleaned up later?"
- **Mode**: `structured`
- **Assertions**: `must_include: ["Jira", "cleanup"]` for basic checks, plus a `rubric` block:
  - Rubric prompt evaluates whether the response covers: (1) creating a Jira cleanup ticket, (2) removing flag + conditional code when released, (3) deleting both FlagKitKey and Flag entries
  - `require_overall_pass: true`, `min_score: 2`
  - `required_check_ids: ["jira-ticket", "remove-flag", "delete-both-entries"]`

**What this demonstrates**:
- *Feature flag skill*: Does the provider know the full lifecycle — not just adding a flag but planning for cleanup?
- *AIDevTools feature*: **Rubric grading** — the AI evaluator path. Tests that the rubric grader receives the prompt with `{{result}}` substituted, returns structured checks, and that `require_overall_pass`, `min_score`, and `required_check_ids` are all enforced. Check the `.rubric.json` artifact to confirm per-check results.

**Validation**: Run with `--provider both`, then inspect the case result JSON and rubric result JSON for each provider. Verify the rubric grader produced the expected check IDs and that scores/pass status are correct.

## - [ ] Phase 4: Edit-mode case with deterministic file/diff checks

**Skills to read**: `ai-dev-tools-debug`

Create case: **`add-bool-flag-edit`**

- **Task**: "Add a new boolean feature flag called 'newChecklistDesign' for a checklist redesign that is in development. Add the FlagKitKey and Flag entry in AppFlags.swift."
- **Mode**: `edit`
- **Assertions**:
  - `must_include: ["newChecklistDesign"]`
  - `deterministic.files_exist: ["FlagKit/Sources/FlagKit/ClientFlags/AppFlags.swift"]`
  - `deterministic.file_contains: {"FlagKit/Sources/FlagKit/ClientFlags/AppFlags.swift": ["newChecklistDesign", "featurePhase: .development"]}`
  - `deterministic.diff_contains: ["newChecklistDesign", ".development"]`

**What this demonstrates**:
- *Feature flag skill*: Can the provider actually edit the real file and place the flag correctly — not just describe the code, but write it?
- *AIDevTools feature*: **Edit mode + deterministic checks** — the most complex grading path. Tests that: (1) the provider runs with `--dangerously-skip-permissions`, (2) `files_exist` confirms the file is present, (3) `file_contains` reads the actual file post-edit, (4) `diff_contains` verifies the git diff includes expected strings, (5) git reset cleans up after. This validates the core edit-mode pipeline.

**Validation**: Run with `--repo` flag (required for edit mode) and `--provider both`. Verify the diff in the raw artifacts shows actual file changes for each provider. Confirm git status is clean after each run (reset worked).

## - [ ] Phase 5: Edit-mode case with rubric quality check

**Skills to read**: `ai-dev-tools-debug`

Create case: **`add-bool-flag-edit-quality`**

- **Task**: "Add a new boolean feature flag called 'offlineSync' for an offline sync feature in development. Add the FlagKitKey and Flag entry in AppFlags.swift."
- **Mode**: `edit`
- **Assertions**:
  - `deterministic.diff_contains: ["offlineSync", ".development"]`
  - `deterministic.diff_not_contains: [".release"]` — provider should not set release phase
  - `rubric` block checking: (1) FlagKitKey uses `Self("offlineSync")` not the avoidMemberCheck initializer, (2) Flag entry placement, (3) correct default values

**What this demonstrates**:
- *Feature flag skill*: Same skill but with a different flag name — confirms the provider generalizes rather than memorizing one example.
- *AIDevTools feature*: **Edit mode + rubric + diff_not_contains**. Tests that: (1) `diff_not_contains` correctly fails if unwanted strings appear in the diff, (2) rubric grading works in edit mode (the rubric grader reads the live repo before reset). This is a key combination for quality gating.

**Validation**: Run with `--provider both`. Inspect the rubric result for each provider to verify the AI grader could read the actual edited file. Confirm `diff_not_contains` was evaluated (check the grading detail in case result JSON).

## - [ ] Phase 6: Trace command assertions

**Skills to read**: `ai-dev-tools-debug`

Create case: **`query-flag-usage`**

- **Task**: "Show how to check the value of a boolean feature flag called 'newChecklistDesign' in Swift code."
- **Mode**: `structured`
- **Assertions**:
  - `must_include: ["Flags.boolValue(.newChecklistDesign)"]`
  - `must_not_include: ["boolValueWithKey"]`
  - `deterministic.max_commands: 15` — a simple query shouldn't need many tool calls
  - `deterministic.max_repeated_commands: 3` — detect if the provider thrashes on the same command

**What this demonstrates**:
- *Feature flag skill*: Does the provider know the correct API for querying a boolean flag?
- *AIDevTools feature*: **Trace command assertions** — `max_commands` and `max_repeated_commands`. Tests that the eval system correctly counts tool calls from the provider's raw output and enforces limits. If the provider uses too many commands or repeats the same one, the case should fail. This validates the tool-call analysis pipeline.

**Validation**: Run with `--provider both` and inspect the grading results for the trace assertions for each provider. Check the raw stdout to see actual tool call count. Verify the assertion correctly reports pass/fail.

## - [ ] Phase 7: Negative test with should_trigger

**Skills to read**: `ai-dev-tools-debug`

Create case: **`unrelated-task-no-trigger`**

- **Task**: "How do I set up a new Core Data model for storing flight plans?"
- **Mode**: `structured`
- **Fields**: `skill_hint: "feature-flags"`, `should_trigger: false`
- **Assertions**: `must_not_include: ["FlagKitKey", "FlagKit", "featurePhase"]` — the response should have nothing to do with feature flags

**What this demonstrates**:
- *Feature flag skill*: Negative validation — the feature flag skill should NOT activate for unrelated tasks. This prevents false-positive skill triggers.
- *AIDevTools feature*: **`skill_hint` + `should_trigger: false`**. Tests that the eval system can evaluate whether a skill correctly did NOT fire. This is important for ensuring skills have proper scoping and don't inject irrelevant context.

**Validation**: Run with `--provider both`. Both providers should answer about Core Data, not feature flags. Verify the case result for each shows the `should_trigger` check passed.

## - [ ] Phase 8: Full suite validation

**Skills to read**: `ai-dev-tools-debug`

Run the complete rebuilt suite end-to-end:

- `swift run ai-dev-tools-kit run-evals --repo /path/to/sample-app --suite feature-flags --provider both`
- Verify `summary.json` for both claude and codex shows correct passed/failed/skipped counts for all 6 cases
- Spot-check that edit-mode cases leave the repo clean (no uncommitted changes)
- Review any failures to determine if they're skill issues or eval system issues

**Success criteria**:
- All 6 cases run without crashes
- Structured cases produce graded results with correct assertion evaluation
- Edit cases show real diffs and clean up properly
- Rubric cases have populated `.rubric.json` artifacts
- Trace assertions are evaluated (not skipped)
- `should_trigger` negative test is evaluated
- `summary.json` totals match actual case count
