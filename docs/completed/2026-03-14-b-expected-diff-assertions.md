## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-debug` | Eval system debugging — artifact paths, CLI commands, grading layers |
| `swift-testing` | Test style guide — Arrange-Act-Assert pattern |

## Background

Edit-mode eval cases currently have two diff-related mechanisms that don't work well together:

1. **`diffContains` / `diffNotContains`** — flat arrays on `DeterministicChecks` that assert on the git diff string
2. **Hallucination detection** — hardcoded in `RunEvalsUseCase` (not in the grader), flags any edit-mode case where the provider response is non-empty but the diff is empty

The hallucination check produces false positives when the correct behavior is "make no changes." For example, the `discard-nav-title-change` case expects the provider to read a skill, determine no changes are needed, and leave the file alone. The provider does exactly this — but gets flagged because it returned a response explaining why no changes were made.

The root issue is that there's no way for a case to express "I expect no diff." The hallucination check tries to infer intent from the presence of a response, but a response doesn't imply file changes were attempted.

### Design goals

- Let case authors explicitly declare diff expectations: specific strings, or no diff at all
- Remove the implicit hallucination heuristic — make it an explicit assertion instead
- Move all grading logic into `DeterministicGrader` (the hallucination check currently lives in `RunEvalsUseCase`)

## Proposed model

Replace `diffContains` / `diffNotContains` with a single `expectedDiff` object on `DeterministicChecks`:

```json
{
  "deterministic": {
    "expectedDiff": {
      "noDiff": true
    }
  }
}
```

```json
{
  "deterministic": {
    "expectedDiff": {
      "contains": ["iOS26DesignEnabled", "@import IOS26Design;"],
      "notContains": ["navigationItem.title"]
    }
  }
}
```

The three sub-fields:

| Field | Type | Meaning |
|-------|------|---------|
| `noDiff` | `Bool?` | When `true`, asserts the diff is empty. Mutually exclusive with `contains`. |
| `contains` | `[String]?` | Strings that must appear in the diff. Implies the diff must be non-empty. |
| `notContains` | `[String]?` | Strings that must not appear in the diff. Can combine with either `noDiff` or `contains`. |

When `expectedDiff` is present, the grader handles all diff validation. When absent, no diff assertions run (no implicit hallucination guessing).

## Phases

## - [x] Phase 1: Replace `diffContains`/`diffNotContains` with `ExpectedDiff` model

**Principles applied**: Direct field replacement with new nested struct; kept `ExpectedDiff` as its own top-level type for reuse by grader and UI

Remove `diffContains` and `diffNotContains` from `DeterministicChecks`. Add `ExpectedDiff` struct and wire it in:

```swift
public struct ExpectedDiff: Codable, Sendable {
    public let noDiff: Bool?
    public let contains: [String]?
    public let notContains: [String]?
}
```

- Add `expectedDiff: ExpectedDiff?` to `DeterministicChecks`
- Remove `diffContains: [String]?` and `diffNotContains: [String]?`
- Update the `init` accordingly

Files to modify:
- `AIDevToolsKit/Sources/EvalService/Models/EvalCase.swift`

## - [x] Phase 2: Update `DeterministicGrader` to use `ExpectedDiff`

**Principles applied**: Extracted `gradeExpectedDiff` helper to eliminate duplication between `grade()` and `gradeFileChanges()`. Removed dead file/diff logic from `grade()` — file assertions now live exclusively in `gradeFileChanges()`

Replace the existing `diffContains`/`diffNotContains` grading logic with `expectedDiff`:

1. In `grade()` and `gradeFileChanges()`:
   - `noDiff: true` + non-empty diff → error: "expected no diff but changes were found"
   - `contains` with empty diff → error: "expected diff but none found"
   - `contains` strings not in diff → error: "expectedDiff.contains: not found in diff"
   - `notContains` strings in diff → error: "expectedDiff.notContains: found in diff"
2. Remove old `diffContains`/`diffNotContains` handling

Files to modify:
- `AIDevToolsKit/Sources/EvalService/DeterministicGrader.swift`

## - [x] Phase 3: Remove hallucination heuristic from `RunEvalsUseCase`

**Principles applied**: Removed implicit heuristic in favor of explicit `expectedDiff` assertions in the grader

Remove the hardcoded hallucination check from `RunEvalsUseCase.runProvider()`. This logic is now replaced by explicit `expectedDiff` assertions in the grader.

Files to modify:
- `AIDevToolsKit/Sources/EvalFeature/RunEvalsUseCase.swift`

## - [x] Phase 4: Update Mac app UI for `expectedDiff`

**Skills used**: `ai-dev-tools-debug`
**Principles applied**: Replaced old `diffContains`/`diffNotContains` display with `expectedDiff`; also renamed abbreviated local variables (`fc`/`fnc`) per user preference

Update `EvalResultsView.swift` to display `expectedDiff` instead of the old `diffContains`/`diffNotContains` fields. Show:
- "No Diff Expected" when `noDiff: true`
- "Diff Must Contain" for `contains`
- "Diff Must Not Contain" for `notContains`

Files to modify:
- `AIDevTools/Views/EvalResultsView.swift`

## - [x] Phase 5: Migrate existing eval cases

**Skills used**: `ai-dev-tools-debug`
**Principles applied**: Scanned all configured repos and data paths (`~/Desktop/ai-dev-tools/`) for old fields; only one case needed migration

Use `repos list` and `list-cases` to find all cases using diff assertions. Migrate them to `expectedDiff` format.

Known case to migrate:
- `merge-insurance-policy.discard-nav-title-change` in sample-app repo (`~/Desktop/ai-dev-tools/sample-evals/cases/merge-insurance-policy.jsonl`)
  - Currently: `"diffNotContains": ["navigationItem.title"]`
  - New format: `"expectedDiff": { "noDiff": true, "notContains": ["navigationItem.title"] }`

Also scan the AIDevTools repo's demo cases for any usage.

## - [x] Phase 6: Update tests

**Skills used**: `swift-testing`
**Principles applied**: Arrange-Act-Assert pattern; tested through `gradeFileChanges` public API since `gradeExpectedDiff` is private

1. Add tests for `ExpectedDiff` grading:
   - `noDiff: true` with empty diff → passes
   - `noDiff: true` with non-empty diff → fails
   - `contains` with matching diff → passes
   - `contains` with empty diff → fails with "expected diff but none found"
   - `notContains` with forbidden string → fails
   - `notContains` with no match → passes
2. Remove any existing tests that reference `diffContains`/`diffNotContains`

Files to modify:
- `AIDevToolsKit/Tests/EvalServiceTests/DeterministicGraderTests.swift`

## - [x] Phase 7: Validation

**Principles applied**: All tests pass (8 pre-existing failures in CopyrightHeader/DesignKit evals unrelated to this work); Mac app builds; CLI parses migrated case correctly

Run the full test suite:

```bash
cd AIDevToolsKit && swift test
```

Build the Mac app:

```bash
xcodebuild build -project AIDevTools.xcodeproj -scheme AIDevTools -destination 'platform=macOS' -quiet
```

Then verify the CLI parses the updated case correctly:

```bash
swift run ai-dev-tools-kit list-cases --repo /path/to/sample-app --case-id discard-nav-title-change
```

Success criteria:
- All tests pass
- Mac app builds cleanly
- `discard-nav-title-change` case shows `expectedDiff` with `noDiff: true` in list output
- No more false hallucination errors on cases that correctly make no changes
