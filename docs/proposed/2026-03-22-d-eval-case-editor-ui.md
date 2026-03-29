> **2026-03-29 Obsolescence Evaluation:** Plan reviewed, still relevant. The Mac app currently only has read-only views for eval cases (EvalsContainer, EvalResultsView). No eval case editor UI has been implemented - users still need to manually edit JSONL files. This functionality would still be valuable for teams.

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-debug` | Eval case structure, file paths, artifact inspection |
| `swift-architecture` | Architecture guidance for Model-View + Use Cases patterns |

## Background

Eval cases are currently read-only in the Mac app. To edit them, you either use AI or manually edit JSONL files. For the tool to be useful to teams at work, people need to be able to read, create, and edit eval criteria directly in the app. The editor should work with the existing JSONL format — changing the file format is a separate future effort.

---

## Phases

## - [ ] Phase 1: Design the Editor Model

**Skills to read**: `ai-dev-tools-debug`, `swift-architecture`

Define the data flow for editing. The editor needs to:

- Load an eval case from JSONL into an editable model
- Present it in a form
- Save changes back to JSONL

Design the observable model that backs the editor form, following Model-View + Use Cases patterns.

## - [ ] Phase 2: Build the Case Editor View

Build a form-based editor view that lets users:

- Edit the prompt/task description
- Add, remove, and reorder assertions
- Toggle assertion types (required text, forbidden text, file assertions, rubric criteria)
- Edit rubric text for AI-graded checks
- Preview the raw JSONL representation

## - [ ] Phase 3: Create New Cases

Add the ability to create a new eval case from scratch within the editor. Provide sensible defaults and let the user fill in the details.

## - [ ] Phase 4: Integrate into Mac App

Wire the editor into the existing eval detail view. Add edit buttons on existing case cards. Add a "New Case" button to the eval section.

## - [ ] Phase 5: CLI Case Editing

Add CLI subcommands for creating and editing JSONL cases from the command line, mirroring the Mac app editor capabilities:

- `add-case --suite <suite> --id <id> --task "..." [--must-include "..."] [--mode edit|structured]` — create a new case and append it to the suite's JSONL file
- `edit-case --suite <suite> --case-id <id> --task "..." [--must-include "..."]` — update fields on an existing case in-place
- `remove-case --suite <suite> --case-id <id>` — remove a case from a JSONL file

## - [ ] Phase 6: Validation

- Create a new eval case in the editor, save it, and verify the JSONL is correct
- Edit an existing case, save, and run it — verify grading works with the modified case
- Test round-trip: edit → save → reload → verify no data loss
- Test with various assertion types (deterministic and AI-graded)
- Send a screenshot of the Mac app showing the editor UI (see the `open-in-xcode` skill for instructions on capturing screenshots)
