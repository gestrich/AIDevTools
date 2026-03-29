> **2026-03-29 Obsolescence Evaluation:** Plan reviewed, still relevant. No eval generation skill exists in .agents/skills/ directory. This would still be a valuable automation tool for teams to bootstrap eval suites from existing skills, reducing manual JSONL editing effort.

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-debug` | Eval case structure, assertion types, JSONL format |

## Background

Writing eval criteria by hand is tedious and requires deep knowledge of the JSONL format and assertion types. A skill that can analyze an existing AI skill and generate a good set of eval criteria would make it much easier for teams to bootstrap eval suites. It should recommend both deterministic checks (expected strings, file changes) and AI-graded rubric criteria.

---

## Phases

## - [ ] Phase 1: Define the Skill's Scope

Determine what inputs the skill needs (skill file path, repo context) and what it outputs (JSONL eval cases). Document the expected behavior:

- Read a skill's front matter, description, and instructions
- Analyze what the skill is supposed to do
- Generate eval cases covering happy paths, edge cases, and negative tests
- Output in the existing JSONL format

## - [ ] Phase 2: Create the Skill

**Skills to read**: `ai-dev-tools-debug`

Create the skill in `.agents/skills/`. The skill should:

- Accept a skill path or name as context
- Read and understand the target skill's purpose
- Recommend a mix of assertion types: deterministic checks and AI-graded rubric criteria
- Generate well-structured eval cases in JSONL format
- Include edge cases and negative tests (things the skill should NOT do)

## - [ ] Phase 3: Iterate on Quality

Test the skill against several existing skills in the project. Review the generated eval criteria for quality:

- Are the assertions meaningful and not trivially passed?
- Do the rubric criteria capture the important aspects?
- Are edge cases realistic?

Refine the skill's instructions based on results.

## - [ ] Phase 4: Validation

- Run the skill against 3+ existing skills and inspect the generated JSONL
- Load the generated cases into the app and run them
- Verify the generated assertions produce meaningful pass/fail results
