# AI Evaluator

The AI Evaluator runs structured test cases against AI providers (Claude Code and Codex) to measure how well they handle coding tasks. It lets you define what a correct response looks like, run it against one or more providers, and inspect the results with per-case grading details.

Available in the **Evaluator** tab of the Mac app and via `ai-dev-tools-kit run-evals --help` in the CLI.

## Eval Cases

Each eval case is a JSON file describing a task to run and how to grade the result. Cases are grouped into **suites** by directory.

A case specifies:
- **A task or prompt** — the instruction sent to the AI
- **Assertions** — what constitutes a passing result

## Assertion Types

### Text assertions

Check whether the AI's response contains or excludes specific strings:

```json
{
  "id": "my-case",
  "task": "Add a docstring to the `processOrder` function",
  "mustInclude": ["processOrder", "Args:", "Returns:"],
  "mustNotInclude": ["TODO", "pass"]
}
```

### Deterministic checks

Inspect the AI's command trace and file state after execution:

| Check | What it verifies |
|-------|-----------------|
| `filesExist` | Specific files were created |
| `filesNotExist` | Specific files were not created |
| `fileContains` | A file contains certain strings |
| `fileNotContains` | A file does not contain certain strings |
| `traceCommandContains` | The AI issued specific commands (e.g., called a particular tool) |
| `traceCommandOrder` | Commands were issued in a specific order |
| `maxCommands` | The AI didn't use more than N commands |
| `expectedDiff` | The resulting git diff contains (or does not contain) specific content |

Example:
```json
{
  "id": "create-file",
  "task": "Create a file called output.txt containing 'hello'",
  "deterministic": {
    "filesExist": ["output.txt"],
    "fileContains": {
      "output.txt": ["hello"]
    }
  }
}
```

### Rubric grading

Ask a second AI call to grade the response against a custom rubric. Useful for subjective quality checks that can't be captured by string matching:

```json
{
  "id": "code-quality",
  "task": "Refactor the login function to reduce nesting",
  "rubric": {
    "prompt": "Did the AI reduce nesting without changing behavior? Were variable names clear?",
    "minScore": 7
  }
}
```

The grader returns a pass/fail, a numeric score, and notes for each check.

### Skill assertions

Verify that the AI correctly identified and invoked (or did not invoke) a specific Claude Code skill:

```json
{
  "id": "skill-trigger",
  "task": "Fix the build warnings",
  "skills": [
    { "skill": "ai-dev-tools-build-quality", "mustBeInvoked": true }
  ]
}
```

## Eval Modes

Each case runs in one of two modes:

| Mode | Description |
|------|-------------|
| `structured` | AI responds to a prompt; output is graded against text and rubric assertions |
| `edit` | AI performs file edits in a repo; output is graded against deterministic file/diff checks |

## Providers

Cases can be run against multiple providers and compared side-by-side. Supported providers include Claude Code and Codex. Filter to a specific provider using the `--provider` flag or select it in the Mac app.

## Results and Artifacts

After a run, each case produces:
- A **pass/fail** verdict with per-assertion details
- **Saved artifacts** — the AI's output, command trace, and any modified files
- A **summary** across all cases in the suite showing pass rates per provider

Results are stored per repository and can be browsed in the Mac app or inspected via CLI.
