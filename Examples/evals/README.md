# Example Eval Cases

This directory demonstrates the eval directory structure expected by AIDevTools.

## Structure

```
evals/
  cases/
    commit-skill.jsonl       # one JSON object per line, each is an EvalCase
  result_output_schema.json   # JSON Schema for provider structured output
  rubric_output_schema.json   # JSON Schema for rubric grading output
```

## Case Format

Each line in a `.jsonl` file is a JSON object with these fields:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (required) | Unique identifier for the case |
| `task` | string | Description of what the AI should do |
| `input` | string | Input data (e.g., a diff, code snippet) |
| `prompt` | string | Direct prompt override |
| `expected` | string | Expected output for comparison |
| `must_include` | [string] | Strings that must appear in the result |
| `must_not_include` | [string] | Strings that must not appear in the result |
| `skill_hint` | string | Which skill this case targets |
| `should_trigger` | bool | Whether the skill should be triggered |
| `deterministic` | object | Deterministic grading checks (trace assertions) |
| `rubric` | object | Rubric-based grading configuration |

The suite name is derived from the `.jsonl` filename (e.g., `commit-skill.jsonl` becomes suite `commit-skill`).

## Grading

**Deterministic checks** run first — `must_include`, `must_not_include`, and the `deterministic` object fields are evaluated against the provider's output without an additional LLM call.

**Rubric grading** (optional) sends a follow-up prompt to the LLM to evaluate quality. The rubric object includes:
- `prompt` — template for the grading prompt (use `{{result}}` to interpolate the output)
- `require_overall_pass` — whether `overall_pass` must be true
- `min_score` — minimum acceptable score
- `required_check_ids` — list of check IDs that must pass

## Running

From the CLI:
```bash
aidevtools run-evals --eval-dir Examples/evals --provider claude
```

Or configure the eval directory on a repository in the Mac app and run from the skill detail view.
