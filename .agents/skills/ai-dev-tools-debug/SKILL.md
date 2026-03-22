---
name: ai-dev-tools-debug
description: >
  Debugging guide for AIDevTools (evals, plan runner, Mac app). Shows how to discover
  configured repositories, eval cases, artifact paths, plan storage, log files, and
  CLI commands for troubleshooting. Use this skill when: the user reports a bug, asks
  to check eval data, shares a screenshot of eval results or the Mac app, mentions a
  failing case, wants to inspect provider output, or needs to debug plan generation
  or execution. Screenshots of the Mac app are a strong signal to invoke this skill —
  they mean the user wants you to reproduce or investigate using the CLI.
---

# AIDevTools Eval System — Debugging & Data Access

This skill gives you access to the user's real eval data so you can run CLI commands to troubleshoot bugs, inspect results, and reproduce issues. AIDevTools runs coding evals against AI providers (Claude, Codex) and grades output using deterministic checks and rubric-based AI grading.

## Step 1: Build the CLI

The Swift package lives in this repo at `AIDevToolsKit/`. All commands run from there:

```bash
cd <repo-root>/AIDevToolsKit
swift build
swift run ai-dev-tools-kit <subcommand>
```

## Step 2: Discover Configured Repositories

The user's repository configurations live in `repositories.json` inside their **data path** (default: `~/Desktop/ai-dev-tools/`). List them:

```bash
swift run ai-dev-tools-kit repos list
```

This prints each repo's **UUID**, **name**, **path**, and **cases directory**. Use this output to get the actual paths — never assume them.

**IMPORTANT:** When the user mentions a repo by name (e.g. "ios-26"), match it to a configured repo here to find its **path**. Skills for that repo live at `<repo-path>/.claude/skills/` (or `<repo-path>/.agents/skills/`). Always resolve repo paths through `repos list` — do not search for files across the filesystem.

### Repository Configuration Shape

Each entry in `repositories.json`:
```json
{
  "id": "<uuid>",
  "path": "<absolute-path-to-repo>",
  "name": "<display-name>",
  "casesDirectory": "<absolute-or-relative-path>"
}
```

- `casesDirectory` can be absolute or relative (resolved against `path`)
- The **output directory** is auto-derived: `<dataPath>/<name>/`

## Step 3: Find Eval Cases

Cases live under the repo's configured `casesDirectory`:

```
<casesDirectory>/
  cases/
    <suite-name>.jsonl       # One JSON object per line
```

List cases with the CLI:

```bash
# List all cases for a repo
swift run ai-dev-tools-kit list-cases --repo <repo-path>

# Filter by suite
swift run ai-dev-tools-kit list-cases --repo <repo-path> --suite <suite-name>

# Filter by case ID
swift run ai-dev-tools-kit list-cases --repo <repo-path> --case-id <case-id>

# Or use --cases-dir directly instead of --repo
swift run ai-dev-tools-kit list-cases --cases-dir <cases-directory-path>
```

Each case prints its qualified ID, mode, task, assertions, and grading config.

### Eval Case Modes

- `"structured"` (default): Provider returns JSON only, no file edits
- `"edit"`: Provider edits files in the repo AND returns structured output

## Step 4: Find Artifacts & Results

Artifacts are in the **output directory** (`<dataPath>/<repoName>/`):

```
<outputDir>/
  artifacts/
    <provider>/                              # "claude" or "codex"
      summary.json                           # Run summary (total/passed/failed/skipped)
      <suite>.<case-id>.json                 # Per-case grading result
      <suite>.<case-id>.rubric.json          # Rubric result (if rubric configured)
    raw/
      <provider>/
        <suite>.<case-id>.stdout             # Raw provider output (JSONL stream)
        <suite>.<case-id>.stderr             # Raw error output
        <suite>.<case-id>.rubric.stdout      # Rubric grader output
        <suite>.<case-id>.rubric.stderr      # Rubric grader errors
  result_output_schema.json
  rubric_output_schema.json
```

### Reading Results

After discovering paths via `repos list`, read the actual files:

```bash
# Summary for a provider
cat <outputDir>/artifacts/<provider>/summary.json

# Specific case result
cat <outputDir>/artifacts/<provider>/<suite>.<case-id>.json

# Rubric grading result
cat <outputDir>/artifacts/<provider>/<suite>.<case-id>.rubric.json

# Raw provider output (tool calls, responses)
cat <outputDir>/artifacts/raw/<provider>/<suite>.<case-id>.stdout
```

### Summary Shape

```json
{
  "provider": "claude",
  "total": 5,
  "passed": 3,
  "failed": 1,
  "skipped": 1,
  "cases": [
    {
      "caseId": "suite.id",
      "passed": true,
      "errors": [],
      "skipped": [],
      "providerResponse": "...",
      "toolCallSummary": { "attempted": 10, "succeeded": 10, "rejected": 0, "errored": 0 }
    }
  ]
}
```

## Step 5: Running Evals

```bash
# Run a specific case
swift run ai-dev-tools-kit run-evals --repo <repo-path> --case-id <case-id> --provider claude

# Run all cases in a suite
swift run ai-dev-tools-kit run-evals --repo <repo-path> --suite <suite-name> --provider claude

# Run with debug output (shows exact CLI args passed to provider)
swift run ai-dev-tools-kit run-evals --repo <repo-path> --case-id <case-id> --provider claude --debug

# Available providers: claude, codex, both
```

Use `--repo` (not `--cases-dir`) for edit-mode cases so the provider runs in the actual repository.

## Plan Runner CLI Commands

```bash
# Generate a plan from voice/text input (matches repo automatically)
swift run ai-dev-tools-kit plan-runner plan "add dark mode support"

# Generate and immediately execute
swift run ai-dev-tools-kit plan-runner plan "add dark mode support" --execute

# Execute phases from an existing plan
swift run ai-dev-tools-kit plan-runner execute --plan <path-to-plan.md>

# Execute with custom time limit
swift run ai-dev-tools-kit plan-runner execute --plan <path> --max-minutes 60

# Delete a plan and its job directory
swift run ai-dev-tools-kit plan-runner delete --plan <path-to-job-dir-or-plan.md>

# Interactive delete (shows list of all plans)
swift run ai-dev-tools-kit plan-runner delete
```

### Plan Storage

Plans are stored at `~/Desktop/ai-dev-tools/<repoId>/<job-name>/plan.md`. Each job directory may also contain a `worktree/` directory and `*.log` files.

### Plan Execution Logs

Each plan phase execution writes two types of logs:

**1. AI output logs** — the full Claude output for each phase:
```
<dataPath>/<repoName>/plan-logs/<plan-name>/phase-<N>.stdout
```

Example: `~/Desktop/ai-dev-tools/AIDevTools/plan-logs/2026-03-22-f-consolidate-slash-commands-into-skills/phase-2.stdout`

These are written on both success and failure (partial output is captured even when a phase fails). One file per phase, overwritten on re-execution.

**2. Structured error logs** — phase start/complete/fail events written to the app-wide log via `Logger(label: "PlanRunner")`:
```bash
# Filter plan execution errors
cat ~/Library/Logs/AIDevTools/aidevtools.log | jq 'select(.label == "PlanRunner")'

# Just errors (includes underlying error message and path to the .stdout log file)
cat ~/Library/Logs/AIDevTools/aidevtools.log | jq 'select(.label == "PlanRunner" and .level == "error")'
```

Error log entries include a `logFile` metadata field pointing to the corresponding `.stdout` file for cross-referencing.

## Other CLI Commands

```bash
# Show formatted output from a completed run
swift run ai-dev-tools-kit show-output --repo <repo-path> --provider claude

# Delete all prior artifacts
swift run ai-dev-tools-kit clear-artifacts --repo <repo-path>

# List skills for a repo
swift run ai-dev-tools-kit skills <repo-path>

# Manage repos
swift run ai-dev-tools-kit repos add <path>
swift run ai-dev-tools-kit repos remove <uuid>
swift run ai-dev-tools-kit repos update <uuid>
```

## Grading Layers

1. **Response text:** `must_include` / `must_not_include` on the provider's structured output
2. **Deterministic checks:** `filesExist`, `filesNotExist`, `fileContains`, `fileNotContains`, `diffContains`, `diffNotContains`, `traceCommandContains`, `traceCommandNotContains`, `traceCommandOrder`, `maxCommands`, `maxRepeatedCommands`, `skillMustBeInvoked`, `skillMustNotBeInvoked`, `referenceFileMustBeRead`, `referenceFileMustNotBeRead`
3. **Rubric grading:** AI evaluator with `overall_pass`, `score`, and per-check results

## Edit-Mode Grading Order

1. Provider runs and edits files
2. Git diff captured
3. Deterministic file/diff assertions run
4. Rubric grading runs (can read live repo state)
5. Git reset cleans up changes

## Permissions

- Edit-mode cases pass `--dangerously-skip-permissions` to Claude CLI automatically
- Structured-mode cases do not (no file edits needed)

## Tool Call Summary

Both providers produce a `toolCallSummary`:
- **Claude:** Correlates `tool_use`/`tool_result` events by ID. "rejected" = permission denied.
- **Codex:** Counts `command_execution` items by exit code. No "rejected" concept.
- **Hallucination detection:** Warning added if diff is empty but provider claims changes.

## Logs

AIDevTools writes structured JSON-line logs to `~/Library/Logs/AIDevTools/aidevtools.log`. Both the Mac app and CLI write to this file via `swift-log` and `LoggingSDK`.

```bash
# Read all logs
cat ~/Library/Logs/AIDevTools/aidevtools.log

# Read logs as formatted JSON
cat ~/Library/Logs/AIDevTools/aidevtools.log | jq .

# Filter by label (e.g. PlanRunnerModel)
cat ~/Library/Logs/AIDevTools/aidevtools.log | jq 'select(.label == "PlanRunnerModel")'

# Filter by level
cat ~/Library/Logs/AIDevTools/aidevtools.log | jq 'select(.level == "error")'

# Tail live (while app is running)
tail -f ~/Library/Logs/AIDevTools/aidevtools.log | jq .
```

### Adding Logs for Debugging

Use `import Logging` and create a logger with `Logger(label: "AIDevTools.<ComponentName>")`. The `LoggingSDK` module provides `AIDevToolsLogging.bootstrap()` which is called at app startup.

**For CLI debugging:** Add log statements, run the CLI command, then check output with `cat ~/Library/Logs/AIDevTools/aidevtools.log`.

**For Mac app debugging:** Since the Mac app runs separately, tell Bill you are adding log statements to help troubleshoot, explain what information the logs will capture, then ask Bill to run the app and trigger the relevant action. After the run, read the log file to see what happened.

Log files auto-rotate at 10MB.

## Debugging Tips

- **Provider didn't edit files?** Check raw stdout for permission errors. With `--debug`, verify CLI args include `--dangerously-skip-permissions` for edit-mode cases.
- **Empty diff for edit-mode?** Check `toolCallSummary.rejected` or search raw stdout for `"is_error":true`.
- **Permissions flag missing?** Verify `"mode": "edit"` in the JSONL case definition.
- **Rubric grading failed?** Read the rubric result JSON — per-check `notes` explain what the grader found.
- **Rubric check IDs mismatch?** `required_check_ids` must match what the grader returns. If unpredictable, omit and use `require_overall_pass` + `min_score`.
- **diffNotContains false positive?** Git diffs include 3 context lines. Nearby code may contain the forbidden string even though the provider didn't add it.
- **Wrong cwd?** Check `"cwd"` in the first line of raw stdout (`"type":"system","subtype":"init"`).
- **Stale artifacts?** Artifacts are overwritten each run. Use `--keep-traces` to preserve JSONL traces.
- **Plan phase failed?** Check the AI output log at `<dataPath>/<repoName>/plan-logs/<plan-name>/phase-<N>.stdout` for Claude's full output, then check `~/Library/Logs/AIDevTools/aidevtools.log` filtered by `label == "PlanRunner"` for the structured error with the underlying cause.
