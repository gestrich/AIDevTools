# AIDevTools

A Swift package for evaluating AI provider CLIs (Claude, Codex) on skill-guided code transformations. It runs eval cases through provider CLIs, grades results deterministically and via rubric, and writes artifacts.

## Motivation

This project was inspired by OpenAI's [Eval Skills](https://developers.openai.com/blog/eval-skills/) blog post, which argues that agent skill improvement requires structured evaluation rather than subjective assessment. Instead of asking "does this feel better?", evals let you ask concrete questions like: Did the agent invoke the skill? Did it run the expected commands? Did it produce the right output?

The key insight is that reproducible measurement converts subjective impressions into actionable data — define success upfront, start with lightweight deterministic checks, layer in model-based grading for qualitative requirements, and grow coverage from real failures.

## Quick Start

```bash
cd dev-tools/AIDevTools

# Build
swift build

# Run unit tests (fast — uses mock adapters)
swift test --skip EvalIntegrationTests

# Run integration tests (slow — calls real Claude/Codex CLIs)
swift test --filter EvalIntegrationTests
```

## Architecture

The package follows a 4-layer architecture:

```
AIDevToolsApp       (Apps)      CLI entry point — maps args to use cases
    ↓
EvalFeature         (Features)  Orchestrates eval runs — RunEvalsUseCase, RunCaseUseCase
    ↓
EvalService         (Services)  Pure grading logic — DeterministicGrader, RubricGrader, PromptBuilder
EvalSDK             (SDKs)      Provider adapters — ClaudeAdapter, CodexAdapter, output parsers
```

Dependencies flow downward only. Each layer is a separate target with its own test target.

### Claude & Anthropic Targets

**SDKs (stateless, single-operation wrappers):**

| Target | Wraps | Description |
|--------|-------|-------------|
| `AnthropicSDK` | SwiftAnthropic HTTP API | Direct Anthropic Messages API — send messages, stream responses, tool calling |
| `ClaudeCLISDK` | `/usr/local/bin/claude` binary | Claude Code CLI subprocess — structured output, stream-json parsing, result events |
| `ClaudePythonSDK` | Python `claude_agent.py` script | Claude Agent via Python subprocess — JSON stdin/stdout, inactivity watchdog |
| `SkillScannerSDK` | Filesystem scan | Scans `.agents/skills/`, `.claude/skills/`, `.claude/commands/`, and `~/.claude/commands/` for skill `.md` files |

**Services (shared models, config, stateful utilities):**

| Target | Built On | Description |
|--------|----------|-------------|
| `AnthropicChatService` | `AnthropicSDK` | Anthropic HTTP chat — orchestration, SwiftData persistence, streaming events |
| `ClaudeCodeChatService` | `ClaudeCLISDK` | Claude Code CLI chat — session management, message queuing, content line parsing |

**Features (use case orchestration):**

| Target | Description |
|--------|-------------|
| `AnthropicChatFeature` | Use cases for Anthropic HTTP chat (send message, manage conversations) |
| `ClaudeCodeChatFeature` | Use cases for Claude Code CLI chat (send message, list sessions, scan skills) |

## How Eval Cases Work

An `EvalCase` defines what to test and how to grade the result:

```swift
EvalCase(
    id: "button-basic",                    // Unique identifier
    suite: "designkit-migration",          // Grouping for filtering
    skillHint: "explicit",                 // "explicit" | "implicit" | nil
    shouldTrigger: true,                   // Whether the skill should activate
    task: "Migrate this view to DK2",      // Task description sent to provider
    input: "Button().dkType(.primary)",    // Code snippet input
    expected: nil,                         // Exact expected output (optional)
    mustInclude: ["Button"],               // Substrings that MUST appear in output
    mustNotInclude: ["dkType"],            // Substrings that must NOT appear
    deterministic: DeterministicChecks(    // Tool event assertions (optional)
        traceCommandContains: ["grep"],    //   Commands that must appear in trace
        traceCommandNotContains: ["rm"],   //   Commands that must NOT appear
        traceCommandOrder: ["cat", "sed"], //   Commands must appear in this order
        maxCommands: 10,                   //   Max total commands allowed
        maxRepeatedCommands: 3             //   Max consecutive repeated commands (thrashing)
    ),
    rubric: RubricConfig(...)              // LLM-based grading (optional)
)
```

### Grading Pipeline

Each case flows through this pipeline:

1. **Prompt Building** — Assembles the prompt from `task` + `input` + `skillHint`
2. **Provider Execution** — Runs the prompt through Claude or Codex CLI
3. **Deterministic Grading** — Checks output against `expected`, `mustInclude`, `mustNotInclude`, tool event assertions
4. **Rubric Grading** (optional) — Runs a second LLM call to grade the output against a rubric prompt
5. **Result Assembly** — `CaseResult.passed = errors.isEmpty`

### What Gets Checked

| Check | Field | Passes When |
|-------|-------|-------------|
| Exact match | `expected` | Normalized output equals expected |
| Required substrings | `mustInclude` | All substrings found in output |
| Forbidden substrings | `mustNotInclude` | No substrings found in output |
| Trace contains | `traceCommandContains` | Each substring found in at least one trace command |
| Trace not contains | `traceCommandNotContains` | No trace command contains the substring |
| Command order | `traceCommandOrder` | Commands appear in the specified sequential order |
| Max commands | `maxCommands` | Total trace commands <= limit |
| Thrashing | `maxRepeatedCommands` | No command repeats consecutively more than the limit |
| Rubric overall | `rubric.requireOverallPass` | LLM grades `overall_pass = true` |
| Rubric score | `rubric.minScore` | LLM score >= threshold |
| Rubric checks | `rubric.requiredCheckIds` | All specified check IDs exist and pass |

Tool event assertions are gated by `ProviderCapabilities.supportsToolEventAssertions`. When the provider doesn't support them, checks are skipped (not failed).

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

## Team

AI Dev Tools
