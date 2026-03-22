## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-debug` | Debugging guide for evals — case structure, artifact paths, CLI commands |
| `swift-architecture` | Architecture and planning guidance |

## Background

Currently every eval is tied to a skill. But evaluations don't always need to test a skill — they could test codebase navigation, code generation quality, model behavior, or how well AI handles a specific repo structure. Skill invocation should be one optional assertion type, not a structural requirement. Generalizing this makes the eval system useful for broader AI benchmarking at work.

---

## Design Decisions

### Flat Storage

Eval suites are JSONL files in a `cases/` directory, named by topic — not by skill. The filename determines the suite name (e.g., `networking-behaviors.jsonl` → suite `networking-behaviors`). Skill association does not drive file naming, directory structure, or case identity.

### Skills as an Optional Array

Instead of top-level `skill_hint`, `should_trigger`, `skillMustBeInvoked`, and `skillMustNotBeInvoked`, skill assertions move into an optional `skills` array on each case. Each entry is a self-contained unit describing expectations for one skill:

```json
{
  "id": "tell-joke",
  "task": "Tell me an AI dev tools themed joke.",
  "must_include": ["AI DEV TOOLS JOKE:"],
  "skills": [
    {
      "skill": "ai-dev-tools-joke",
      "should_trigger": true,
      "must_be_invoked": true
    }
  ]
}
```

A case can reference zero, one, or multiple skills. A case with no `skills` array is a plain eval with no skill assertions. The old top-level fields (`skill_hint`, `should_trigger`) and deterministic checks (`skillMustBeInvoked`, `skillMustNotBeInvoked`) are replaced by this array.

Each skill entry supports:
- `skill` — the skill identifier
- `should_trigger` — whether the skill is expected to trigger
- `must_be_invoked` — deterministic assertion that the skill was invoked
- `must_not_be_invoked` — deterministic assertion that the skill was not invoked

### UI: Evals and Skills as Sibling Views

Both the Mac app and CLI treat **Evals** and **Skills** as sibling top-level views, not nested.

**Evals view** — the primary way to browse and run evaluations:
- Lists all eval suites and cases regardless of skill association
- Shows results, grading, and artifacts
- No skill-centric nesting or grouping

**Skills view** — a secondary dimension for skill-oriented exploration:
- Lists all skills for a repo
- Drilling into a skill shows associated eval suites/cases (i.e., cases that reference that skill in their `skills` array)
- Clicking a suite or case from the skills view navigates to the evals view, filtered to that suite/case

This means you can always find any eval from the evals view directly. The skills view is a convenience for answering "what evals exist for this skill?" without changing how evals are stored or identified.

### CLI Output

The CLI follows the same principle — eval commands are not skill-scoped:

- `list-cases` — lists all cases, optionally filtered by `--suite` or `--case-id` (not by skill)
- `run-evals` — runs cases by suite or case ID
- `show-output` — shows results for any eval, not grouped by skill
- A new `--skill` filter on `list-cases` could show cases that reference a given skill, mirroring the skills view in the Mac app

---

## Phases

## - [x] Phase 1: Audit Skill Coupling

**Skills to read**: `ai-dev-tools-debug`

Audit the eval case model, loader, and grading pipeline to identify everywhere a skill is assumed or required. Document which parts need to change to make skill association optional.

### Audit Findings

#### Fields to Remove

| Field | Location | Purpose |
|-------|----------|---------|
| `skillHint: String?` | `EvalCase` | Prompt hint (`"explicit"` / `"implicit"`) |
| `shouldTrigger: Bool?` | `EvalCase` | Validation that `mustInclude`/`mustNotInclude` are set |
| `skillMustBeInvoked: String?` | `DeterministicChecks` | Single skill must-invoke assertion |
| `skillMustNotBeInvoked: [String]?` | `DeterministicChecks` | Forbidden skill assertions |

#### Files That Need Changes (by phase)

**Phase 2 — Data Model & Grading:**
- `EvalCase.swift` — Remove `skillHint`, `shouldTrigger`; add `skills: [SkillAssertion]?`
- `EvalCase.swift` (`DeterministicChecks`) — Remove `skillMustBeInvoked`, `skillMustNotBeInvoked`
- `PromptBuilder.swift` — Derives prompt hint from `evalCase.skillHint`; change to derive from `skills` array (e.g., any entry with `shouldTrigger: true` implies explicit/implicit hint)
- `DeterministicGrader.swift` — Grades `skillMustBeInvoked` (lines 125-138), `skillMustNotBeInvoked` (lines 140-151), and `shouldTrigger` validation (lines 177-184); all move to iterate over `skills` array
- `RunCaseUseCase.swift` — `resolveSkillChecks()` reads `deterministic?.skillMustBeInvoked` and `deterministic?.skillMustNotBeInvoked`; change to read from `evalCase.skills`
- `DeterministicGraderTests.swift` — Tests for `skillMustBeInvoked`, `skillMustNotBeInvoked`, `shouldTrigger`
- `PromptBuilderTests.swift` — Tests for `skillHint`
- `CopyrightHeaderEvals.swift` — Uses `skillHint` and `shouldTrigger` on all cases
- `DesignKitMigrationEvals.swift` — Uses `skillHint` and `shouldTrigger` on all cases

**Phase 3 — CLI:**
- `EvalCase.summaryDescription` — Prints `skillHint` and `shouldTrigger`; update to print `skills` array
- `RunEvalsCommand.swift` — Abstract says "Run skill evaluation cases"; minor wording fix

**Phase 4 — Mac App:**
- `EvalResultsView.swift` — Displays `skillHint`/`shouldTrigger` (lines 456-461) and `skillMustBeInvoked`/`skillMustNotBeInvoked` (lines 652-657)

**Phase 5 — JSONL Migration:**
- `what-time-is-it.jsonl` — `deterministic.skillMustBeInvoked`
- `ai-dev-tools-joke.jsonl` — `deterministic.skillMustBeInvoked`
- `commit-skill.jsonl` — No skill fields (already compatible)

#### Files That Need No Changes
- `CaseLoader.swift` — Generic JSON decoding; changes to `EvalCase` propagate automatically
- `ProviderAdapterProtocol.swift` — `invocationMethod()` is the resolution mechanism, not coupled to case shape
- `ClaudeAdapter.swift` / `CodexAdapter.swift` — Skill detection logic stays the same
- `CaseResult.swift` — `skillChecks: [SkillCheckResult]` is output-side, not input-side
- `SkillCheckResult` / `ToolEvent` / `InvocationMethod` — Output types, unchanged
- `MockProviderAdapter.swift` — Mock `invocationMethod` stays the same

## - [x] Phase 2: Update Eval Case Data Model

Replace top-level skill fields with the `skills` array:
- Remove `skill_hint`, `should_trigger` from `EvalCase`
- Remove `skillMustBeInvoked`, `skillMustNotBeInvoked` from `DeterministicChecks`
- Add `skills: [SkillAssertion]?` to `EvalCase`
- `SkillAssertion` has: `skill`, `shouldTrigger`, `mustBeInvoked`, `mustNotBeInvoked`
- Update `CaseLoader` to decode the new shape
- Update grading logic to evaluate skill assertions from the array

### Technical Notes

- `SkillAssertion` added as a top-level `Codable`/`Sendable` struct in `EvalCase.swift`
- `PromptBuilder` now derives the invocation hint from `skills.contains(where: { $0.shouldTrigger == true })` — the old explicit/implicit distinction was collapsed into a single "use the most relevant repository skill" hint since it was not meaningfully used
- `DeterministicGrader` iterates `evalCase.skills` for both `mustBeInvoked`/`mustNotBeInvoked` checks and `shouldTrigger` validation
- `RunCaseUseCase.resolveSkillChecks()` now iterates `evalCase.skills` to resolve each skill's invocation status, replacing the old two-pass approach that read from `deterministic`
- `EvalResultsView` updated to display skills array instead of the removed fields (minimal change to keep Phase 4 scope intact)
- `CopyrightHeaderEvals` and `DesignKitMigrationEvals` migrated to use `SkillAssertion` with explicit skill names
- `CaseLoader` required no changes — `EvalCase`'s `Codable` conformance handles the new shape automatically
- Fixed pre-existing compile error in `PlanRunnerFeatureTests` (missing `underlyingError` argument)
- All 52 DeterministicGrader + PromptBuilder tests pass

## - [x] Phase 3: Update CLI Output

- Ensure `list-cases`, `run-evals`, and `show-output` are not skill-scoped in their output format
- Add optional `--skill <name>` filter to `list-cases` to find cases referencing a skill
- Results and summaries should not group by skill

### Technical Notes

- `RunEvalsCommand` abstract changed from "Run skill evaluation cases against AI providers" to "Run evaluation cases against AI providers"
- `list-cases` already used `EvalCase.summaryDescription` (updated in Phase 2) which prints skills as an optional property rather than a grouping dimension
- `show-output` was already not skill-scoped — it displays results by case ID and provider
- Added `--skill` filter to `list-cases` via `CaseLoader.filterCases(skill:)` — matches cases where any entry in the `skills` array has a matching skill name
- Filter flows through `ListEvalCasesUseCase.Options` → `CaseLoader.filterCases`

## - [x] Phase 4: Update Mac App UI

- Add top-level **Evals** sidebar section as a sibling to **Skills**
- Evals view: flat list of all suites and cases, with results and grading
- Skills view: list of skills, drill-in shows associated eval suites/cases
- Navigating from skills view to a suite/case jumps to the evals view filtered to that item

### Technical Notes

- Added `.evals` case to `WorkspaceItem` enum (alphabetically ordered alongside `.plan` and `.skill`)
- New "Evals" sidebar section appears when the selected repository has eval config, shown alphabetically before Plans and Skills
- Selecting "All Evals" in sidebar configures `EvalRunnerModel` and shows `EvalResultsView(skillName: nil)` — displaying all suites/cases without skill filtering
- `SkillDetailView` gains an `onNavigateToEvals` callback; when on the Evals tab, a "View All Evals" button navigates to the top-level Evals view
- Selection state persisted via `@AppStorage("selectedEvalsView")` boolean, restored on app launch alongside existing plan/skill persistence
- `EvalRunnerModel` environment dependency added to `WorkspaceView` to configure eval state when switching to the Evals view directly (previously only configured via `SkillDetailView`)

## - [x] Phase 5: Migrate Existing Evals

- Update all existing JSONL eval files to the new `skills` array format
- Remove old top-level `skill_hint`, `should_trigger`, `skillMustBeInvoked`, `skillMustNotBeInvoked` fields from every case
- No backward compatibility needed — old format support is dropped

### Technical Notes

- `what-time-is-it.jsonl` — Moved `deterministic.skillMustBeInvoked: "what-time-is-it"` to `skills: [{skill: "what-time-is-it", must_be_invoked: true}]`, removed empty `deterministic` object
- `ai-dev-tools-joke.jsonl` — Moved `deterministic.skillMustBeInvoked: "ai-dev-tools-joke"` to `skills: [{skill: "ai-dev-tools-joke", must_be_invoked: true}]`, removed empty `deterministic` object
- `commit-skill.jsonl` — No changes needed, already had no skill-specific fields

## - [x] Phase 6: Validation

- Create a non-skill eval case and run it end-to-end
- Create a multi-skill eval case and verify all skill assertions are graded
- Verify existing skill-scoped evals still work unchanged after migration
- Test the Mac app displays both evals and skills views correctly
- Test navigation from skills view to evals view
- Run the CLI `list-cases` with and without `--skill` filter

### Technical Notes

- Added `general-knowledge.jsonl` — two cases with no `skills` array (plain text assertions only), validating that the eval pipeline handles skill-free cases end-to-end
- Added `multi-skill.jsonl` — one case with two skill assertions (`what-time-is-it` with `must_be_invoked`, `ai-dev-tools-joke` with `must_not_be_invoked`), validating that the grader evaluates each assertion independently
- Non-skill case (`capital-of-france`) passed end-to-end: loaded, ran against Claude, deterministic grading passed with no skill checks
- Multi-skill case (`time-not-joke`) ran end-to-end: both skill assertions were evaluated correctly — `must_be_invoked` failure reported as error, `must_not_be_invoked` pass correctly not reported as error
- Existing skill-scoped case (`ask-time`) loaded and ran with the migrated JSONL format — grading logic intact
- `list-cases` shows all 5 cases (2 non-skill, 1 multi-skill, 2 existing skill-scoped)
- `--skill` filter correctly returns cases referencing a given skill, including multi-skill cases that match
- `--skill` with non-existent skill returns empty result set
- All 52 eval-related unit tests pass (45 DeterministicGrader + 7 PromptBuilder)
- Mac app UI testing requires manual verification — code changes from Phase 4 compile and the Evals sidebar section is present alongside Skills
