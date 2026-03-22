## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | Architecture layer definitions, dependency rules, placement guidance |

## Background

When AI makes changes to a codebase, it's hard to see the big picture — where things landed in the architecture, whether they're in the right layer, and why. The idea is to add a visualization to the planning feature that shows the layers of the architecture and highlights where proposed changes go. Each repository defines its own architecture in a well-known file (`ARCHITECTURE.md`), and during planning the LLM reads that file and outputs a structured JSON representation. The Swift app reads that JSON and renders the diagram — the LLM never generates visual output directly, ensuring consistent styling across plans.

This is a **design-only** phase. No implementation — just a document defining the concept, data model, and integration approach.

---

## Phases

## - [ ] Phase 1: Architecture Doc, SVG Generation, and Change Highlighting

**Skills to read**: `swift-architecture`

Define a convention where each repository contains an `ARCHITECTURE.md` file that describes its architectural layers, modules, and their relationships. During plan generation, the LLM reads this file and outputs a JSON file conforming to a defined schema. The Swift app renders the diagram from that JSON — the LLM should not generate SVG or any visual output directly, so that styling (node shapes, colors, layout) stays consistent across plans.

- Define the expected format/structure of `ARCHITECTURE.md` (layers, modules per layer, dependency directions)
- This is per-repo, not a static/global definition of layers
- Define a JSON schema for the architecture diagram (layers, modules, which modules are affected by proposed changes)
- The LLM reads `ARCHITECTURE.md` and has instructions for how to produce JSON conforming to this schema
- The LLM writes the JSON to disk as part of plan generation
- Map proposed file additions/modifications to their corresponding architecture layer in the JSON
- When plan execution completes, the Swift app reads the JSON and renders the architecture diagram in the UI with consistent styling (colors for layer boxes, layout rules, fonts)

## - [ ] Phase 2: Graphical UI Integration

Design the UI for viewing the architecture diagram within the planning detail:

- Show the generated SVG in the plan detail view
- Allow the user to select a layer/module and see which proposed changes affect it
- Consider how this integrates alongside the existing phase checklist in the plan detail view

## Later Steps (Not Yet Scoped)

- Violation detection (e.g., "this looks like business logic but it's in the UI layer")
- Architectural principles/rules per layer and annotation of which principle justifies a placement
- "Why here?" interactive justification from AI
- Refactoring detection, violation alerts

## - [ ] Phase 3: Validation

- Review the design document with a real plan to verify the model is expressive enough
- Walk through a sample plan and manually annotate where changes would land — confirm the model captures it
- Identify any gaps or missing concepts before implementation begins
