# AI Planning

AI Planning generates phased implementation plans from plain-language descriptions and executes them one phase at a time using Claude Code.

Available in the **Plans** tab of the Mac app and via `ai-dev-tools-kit plan --help` in the CLI.

## How It Works

Describe what you want to build, and the planner breaks it down into a numbered sequence of phases — each with a description and a set of tasks. Phases are executed sequentially; you trigger each one manually and watch the output live before moving to the next.

Plans are stored as markdown files in the repository's data directory and persist across sessions. You can pause mid-plan, resume later, and view the history of completed phases.

## Key Concepts

**Plan generation** — Provide a natural-language description of the feature or change. The planner uses Claude to produce a structured, phased plan tailored to the repository context.

**Phase execution** — Each phase is a discrete Claude Code session. The Mac app and CLI both show live streaming output as the phase runs, with elapsed time tracking per phase and for the overall plan.

**Completion checklists** — Each phase includes a checklist of what was expected to be done. After execution, verify the checklist items were completed before advancing.

**Per-repository plans** — Plans are scoped to a specific repository and stored separately for each one. Multiple plans can exist for the same repository (e.g., different features in progress at once).
