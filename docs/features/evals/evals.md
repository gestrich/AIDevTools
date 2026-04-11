# AI Evaluator

The AI Evaluator runs structured test cases against AI providers (Claude Code and Codex) to measure how well they handle coding tasks. It lets you define what a correct response looks like, run it against one or more providers, and inspect the results with per-case grading details.

Available in the **Evaluator** tab of the Mac app and via `ai-dev-tools-kit run-evals --help` in the CLI.

## Motivation

This feature was inspired by OpenAI's [Eval Skills](https://developers.openai.com/blog/eval-skills/) blog post, which argues that agent skill improvement requires structured evaluation rather than subjective assessment. Instead of asking "does this feel better?", evals let you ask concrete questions like: Did the agent invoke the skill? Did it run the expected commands? Did it produce the right output?

The key insight is that reproducible measurement converts subjective impressions into actionable data — define success upfront, start with lightweight deterministic checks, layer in model-based grading for qualitative requirements, and grow coverage from real failures.

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

## CLI Usage

```bash
# Run evals with Codex
swift run ai-dev-tools run-evals --eval-dir /path/to/evals --provider codex

# Run evals with Claude
swift run ai-dev-tools run-evals --eval-dir /path/to/evals --provider claude

# Run both providers
swift run ai-dev-tools run-evals --eval-dir /path/to/evals --provider both

# Filter by suite or case ID
swift run ai-dev-tools run-evals --eval-dir /path/to/evals --provider claude --suite designkit-migration
swift run ai-dev-tools run-evals --eval-dir /path/to/evals --provider claude --case-id button-basic

# Keep trace logs
swift run ai-dev-tools run-evals --eval-dir /path/to/evals --provider claude --keep-traces
```

## Adding New Eval Cases

### 1. Create an Eval File

Add a new file in `Tests/EvalIntegrationTests/`:

```swift
import Testing
import EvalService

enum MySkillEvals {
    static let cases: [EvalCase] = [
        EvalCase(
            id: "basic-transform",
            suite: "my-skill",
            skillHint: "explicit",
            shouldTrigger: true,
            task: "Transform this code using my-skill conventions",
            input: """
            // code to transform
            """,
            mustInclude: ["expected pattern"],
            mustNotInclude: ["old pattern"]
        ),
    ]
}

@Suite("My Skill Evals", .tags(.integration))
struct MySkillEvalTests {
    @Test(arguments: MySkillEvals.cases)
    func evalCase(_ eval: EvalCase) async throws {
        try await runEval(eval)
    }
}
```

Each `EvalCase` in the `arguments` array appears as an individual test in the test navigator.

### 2. Add Negative Tests (Expected Failures)

Test that the skill does NOT activate for out-of-scope tasks:

```swift
enum MySkillEvals {
    static let negativeCases: [EvalCase] = [
        EvalCase(
            id: "out-of-scope",
            suite: "my-skill",
            skillHint: "explicit",
            shouldTrigger: false,
            task: "Do something the skill can't do",
            input: "unrelated code",
            mustNotInclude: ["skill-specific pattern"]
        ),
    ]
}

@Suite("My Skill Evals — Negative", .tags(.integration))
struct MySkillNegativeEvalTests {
    @Test(arguments: MySkillEvals.negativeCases)
    func evalCaseExpectingFailure(_ eval: EvalCase) async throws {
        try await runEvalExpectingFailure(eval)
    }
}
```

`runEvalExpectingFailure` asserts that the case does NOT pass — use it when you expect the AI to produce output that violates your assertions.

### 3. Choose Your Assertions

**Start simple** — `mustInclude` + `mustNotInclude` cover most cases:

```swift
// The output should contain the new API and NOT contain the old API
mustInclude: ["NewAPI.call()"],
mustNotInclude: ["OldAPI.call()"]
```

**Add tool event checks** for efficiency and safety:

```swift
deterministic: DeterministicChecks(
    traceCommandNotContains: ["rm -rf"],  // Safety: no destructive commands
    maxCommands: 15,                       // Efficiency: don't waste tokens
    maxRepeatedCommands: 3                 // No thrashing
)
```

**Add rubric grading** for subjective quality:

```swift
rubric: RubricConfig(
    prompt: """
    Grade the following code transformation result.
    Input: {{input}}
    Result: {{result}}
    Check: Does it follow SwiftUI best practices?
    """,
    requireOverallPass: true,
    minScore: 7,
    requiredCheckIds: ["follows-conventions", "no-deprecated-apis"]
)
```

## Test Organization

| Target | Speed | What It Tests |
|--------|-------|---------------|
| `EvalServiceTests` | Fast | Grading logic, prompt building, rubric parsing |
| `EvalSDKTests` | Fast | Output parsers for Claude/Codex CLI output |
| `EvalFeatureTests` | Fast | Use case orchestration with mock adapters |
| `EvalIntegrationTests` | Slow | End-to-end with real provider CLIs |

The `GradingValidationTests` in `EvalFeatureTests` systematically prove every grading capability catches both success and failure using mock adapters — run these to verify the grading framework itself is correct.

To run tests:

```bash
# Fast — uses mock adapters
swift test --skip EvalIntegrationTests

# Slow — calls real Claude/Codex CLIs
swift test --filter EvalIntegrationTests
```
