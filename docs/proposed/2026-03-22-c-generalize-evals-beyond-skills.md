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

## - [ ] Phase 1: Audit Skill Coupling

**Skills to read**: `ai-dev-tools-debug`

Audit the eval case model, loader, and grading pipeline to identify everywhere a skill is assumed or required. Document which parts need to change to make skill association optional.

## - [ ] Phase 2: Update Eval Case Data Model

Replace top-level skill fields with the `skills` array:
- Remove `skill_hint`, `should_trigger` from `EvalCase`
- Remove `skillMustBeInvoked`, `skillMustNotBeInvoked` from `DeterministicChecks`
- Add `skills: [SkillAssertion]?` to `EvalCase`
- `SkillAssertion` has: `skill`, `shouldTrigger`, `mustBeInvoked`, `mustNotBeInvoked`
- Update `CaseLoader` to decode the new shape
- Update grading logic to evaluate skill assertions from the array

## - [ ] Phase 3: Update CLI Output

- Ensure `list-cases`, `run-evals`, and `show-output` are not skill-scoped in their output format
- Add optional `--skill <name>` filter to `list-cases` to find cases referencing a skill
- Results and summaries should not group by skill

## - [ ] Phase 4: Update Mac App UI

- Add top-level **Evals** sidebar section as a sibling to **Skills**
- Evals view: flat list of all suites and cases, with results and grading
- Skills view: list of skills, drill-in shows associated eval suites/cases
- Navigating from skills view to a suite/case jumps to the evals view filtered to that item

## - [ ] Phase 5: Migration & Backward Compatibility

- Support both old (`skill_hint`, `skillMustBeInvoked`) and new (`skills` array) formats during a transition period
- Migrate existing JSONL files to the new format
- Log a deprecation warning when old fields are encountered

## - [ ] Phase 6: Validation

- Create a non-skill eval case and run it end-to-end
- Create a multi-skill eval case and verify all skill assertions are graded
- Verify existing skill-scoped evals still work unchanged after migration
- Test the Mac app displays both evals and skills views correctly
- Test navigation from skills view to evals view
- Run the CLI `list-cases` with and without `--skill` filter
