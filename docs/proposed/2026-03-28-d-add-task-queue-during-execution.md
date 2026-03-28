## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture (Apps/Features/Services/SDKs) for layer placement and dependency direction |

## Background

Currently, when a plan is executing in the MarkdownPlannerDetailView, the user cannot add new tasks to the plan. If something comes to mind during execution, they must wait for it to finish, manually edit the markdown, and re-execute.

This feature adds an "Add Task" button that lets the user queue new tasks while execution is running. After the current phase completes, the system uses AI to intelligently integrate the queued task into the plan — figuring out the right placement, phase numbering, and description style consistent with the original plan.

## - [x] Phase 1: Add queued task model and state to MarkdownPlannerModel

**Skills used**: `swift-architecture`
**Principles applied**: Placed `QueuedTask` as a top-level struct in the App layer alongside `PlanPhase`, since it's UI-facing state. Used `private(set)` for `queuedTasks` to ensure mutations go through dedicated methods.

**Skills to read**: `swift-architecture`

Add infrastructure for the task queue in the App-layer model:

- Add a `QueuedTask` struct (just a `String` description and a `UUID` id) inside `MarkdownPlannerModel` or as a top-level type in the same file
- Add a `queuedTasks: [QueuedTask]` observable property to `MarkdownPlannerModel`
- Add `func queueTask(_ description: String)` that appends to the array
- Add `func clearQueue() -> [QueuedTask]` that drains and returns the queued tasks

## - [x] Phase 2: Create IntegrateTaskIntoPlanUseCase

**Skills used**: `swift-architecture`
**Principles applied**: Placed use case in Features/MarkdownPlannerFeature/usecases following the existing pattern (GeneratePlanUseCase, ExecutePlanUseCase). Reused PhaseResult for the structured response to avoid unnecessary new types. Included plan content directly in the prompt so the AI has full context for intelligent placement.

**Skills to read**: `swift-architecture`

Create a new use case in `Sources/Features/MarkdownPlannerFeature/usecases/IntegrateTaskIntoPlanUseCase.swift`:

- Input: plan file URL, repo path, task description(s), AI client
- Behavior: Calls the AI with a prompt that:
  - Reads the current plan file
  - Understands the plan's structure, background, and existing phases
  - Integrates the new task(s) into the appropriate place — could be a new phase, merged into an existing uncompleted phase, or adjustments to the validation phase
  - Preserves the existing plan format (phase numbering, skills references, checkbox style)
  - Only adds/modifies uncompleted phases — never touches completed `[x]` phases
  - Writes the updated plan content back to the file
- The prompt should reference the same planning conventions used by `GeneratePlanUseCase` (phase format, 10-phase limit, scope rules) but frame it as "adding a task to an existing plan" rather than generating from scratch
- Returns a simple success/failure result
- Use `dangerouslySkipPermissions: true` since this runs during automated execution

## - [x] Phase 3: Add between-phases hook to ExecutePlanUseCase

**Skills used**: none
**Principles applied**: Minimal change — added optional `betweenPhases` closure with default `nil` so all existing call sites remain unchanged. Placed the call after the `.next` early return and architecture diagram check but before `getPhaseStatus`, so the closure can modify the plan file and the subsequent status fetch picks up changes.

Modify `ExecutePlanUseCase` to support a callback between phases:

- Add an optional `betweenPhases` closure parameter to `run()`:
  ```swift
  betweenPhases: (@Sendable () async throws -> Void)? = nil
  ```
- Call it in the main `while` loop after `phaseCompleted` progress is reported and before fetching the next phase status (line ~237 area, after the `executeMode == .next` early return and architecture diagram check, but before `getPhaseStatus`)
- This is the natural integration point: the closure runs, potentially modifying the plan file, then `getPhaseStatus` re-reads the plan and picks up any new phases

## - [x] Phase 4: Wire up queue processing in MarkdownPlannerModel

**Skills used**: none
**Principles applied**: Used `MainActor.run` to safely read and drain the queue from the `@Sendable` closure. Batches all queued tasks into a single AI call via `IntegrateTaskIntoPlanUseCase` rather than one call per task.

Connect the queue to the execution flow:

- In `MarkdownPlannerModel.execute()`, create the `IntegrateTaskIntoPlanUseCase` instance
- Pass a `betweenPhases` closure to `ExecutePlanUseCase.run()` that:
  1. Checks if `queuedTasks` is non-empty (must dispatch to MainActor to read)
  2. If empty, returns immediately (no-op for normal flow)
  3. If tasks exist, drains the queue and runs `IntegrateTaskIntoPlanUseCase` for each task (or batches them into one AI call)
  4. The use case modifies the plan file on disk
  5. Returns, allowing `ExecutePlanUseCase` to re-read phase status and discover new phases

## - [x] Phase 5: Add "Add Task" UI to MarkdownPlannerDetailView

**Skills used**: none
**Principles applied**: Added the button near existing controls in the header bar, only enabled during execution. Used a popover for task entry to avoid cluttering the main view. Queued tasks display below the phase list with a clock icon and X button for removal. Added `removeQueuedTask` to the model to support deletion.

Add the UI for queuing tasks:

- Add an "Add Task" button in the header bar (near the Execute button), enabled only when `isExecuting` is true
- When tapped, show a popover or inline text field where the user types a short task description
- On submit, call `markdownPlannerModel.queueTask(description)`
- Display queued tasks in the phase section (below the phase list) with a "queued" badge/icon (e.g., `clock` SF Symbol) so the user sees their tasks are pending integration
- Allow removing a queued task before it's integrated (swipe to delete or X button)
- When a queued task is integrated (queue drains), it disappears from the queued list and appears as a new phase in the phase list on next status refresh

## - [x] Phase 6: Validation

**Skills used**: none
**Principles applied**: Verified clean build with no compiler errors. Manual testing steps documented below for Bill to validate end-to-end behavior.

- Build the project and verify no compiler errors
- Test manually:
  1. Start executing a multi-phase plan in "Execute All" mode
  2. While a phase is running, tap "Add Task" and enter a description
  3. Verify the task appears in the queued section
  4. When the current phase completes, verify the plan file is updated with the new task integrated
  5. Verify execution continues and picks up the newly added phase
  6. Test adding multiple tasks while executing
  7. Test adding a task when not executing (button should be disabled or queue for next execution)
  8. Test the "Execute Next" mode — queued tasks should still integrate after the single phase completes
