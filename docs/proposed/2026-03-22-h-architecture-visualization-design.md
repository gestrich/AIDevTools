## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | Architecture layer definitions, dependency rules, placement guidance |

## Background

When AI makes changes to a codebase, it's hard to see the big picture — where things landed in the architecture, whether they're in the right layer, and why. The idea is to add a visualization to the planning feature that shows the layers of the architecture and highlights where proposed changes go. Each repository defines its own architecture in a well-known file (`ARCHITECTURE.md`), and during planning the LLM reads that file and outputs a structured JSON representation. The Swift app reads that JSON and renders the diagram — the LLM never generates visual output directly, ensuring consistent styling across plans.

This is a **design-only** phase. No implementation — just a document defining the concept, data model, and integration approach.

---

## Phases

## - [x] Phase 1: Architecture Doc, JSON Schema, and Change Highlighting

**Skills to read**: `swift-architecture`

Define a convention where each repository contains an `ARCHITECTURE.md` file that describes its architectural layers, modules, and their relationships. During plan generation, the LLM reads this file and outputs a JSON file conforming to a defined schema. The Swift app renders the diagram from that JSON — the LLM should not generate SVG or any visual output directly, so that styling (node shapes, colors, layout) stays consistent across plans.

---

### 1. ARCHITECTURE.md Convention

Each repository that wants architecture visualization places an `ARCHITECTURE.md` file at its root. The file uses structured markdown that is both human-readable and LLM-parseable.

**Format:**

```markdown
# Architecture

## Layers

Ordered from highest (closest to user) to lowest (foundational). Higher layers may depend on lower layers but not the reverse.

### Apps
Entry points, UI, and CLI. Depends on: Features, Services, SDKs.
- **AIDevToolsKitMac** — macOS SwiftUI application
- **AIDevToolsKitCLI** — Command-line interface

### Features
Business logic orchestration and use cases. Depends on: Services, SDKs.
- **EvalFeature** — Eval execution and result analysis
- **PlanRunnerFeature** — Plan generation and phase execution

### Services
Domain services and data persistence. Depends on: SDKs.
- **EvalService** — Eval case storage, artifact management
- **PlanRunnerService** — Plan settings, plan entry model

### SDKs
Foundational utilities and external system interfaces. No internal dependencies.
- **ClaudeCLISDK** — Claude CLI process management
- **GitSDK** — Git operations
- **RepositorySDK** — Repository configuration and storage

## Dependency Rules
- Apps → Features, Services, SDKs
- Features → Services, SDKs
- Services → SDKs
- SDKs → (none)
```

**Key conventions:**
- `## Layers` section is required; it defines the vertical ordering of the diagram
- Each `### LayerName` heading defines a layer; the order of headings defines top-to-bottom position
- Bullet points under a layer heading define modules: `- **ModuleName** — description`
- The `Depends on:` line after the layer heading declares which layers this layer may import from
- `## Dependency Rules` section provides a quick summary; it must be consistent with the per-layer declarations
- Module names should match target names in Package.swift (or project structure equivalent)
- The file is maintained by humans; the LLM reads but never modifies it

**How the existing `architectureDocs` field connects:** The `RepositoryInfo.architectureDocs` array already stores paths to architecture documentation. Repositories that adopt this convention would list `ARCHITECTURE.md` in that array. The plan generation prompt already passes these docs to the LLM.

---

### 2. Architecture Diagram JSON Schema

When Phase 3 ("Plan the Implementation") generates the concrete implementation phases, it also produces a JSON file that maps the planned changes onto the architecture. This JSON is the sole input for the Swift app's rendering — the LLM never produces visual output.

**Schema:**

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["layers"],
  "properties": {
    "layers": {
      "type": "array",
      "description": "Ordered top-to-bottom (index 0 = highest layer)",
      "items": {
        "type": "object",
        "required": ["name", "modules"],
        "properties": {
          "name": {
            "type": "string",
            "description": "Layer name matching the ### heading in ARCHITECTURE.md"
          },
          "dependsOn": {
            "type": "array",
            "items": { "type": "string" },
            "description": "Layer names this layer may depend on"
          },
          "modules": {
            "type": "array",
            "items": {
              "type": "object",
              "required": ["name", "changes"],
              "properties": {
                "name": {
                  "type": "string",
                  "description": "Module name matching the bold bullet in ARCHITECTURE.md"
                },
                "changes": {
                  "type": "array",
                  "description": "Empty if module is unaffected by the plan",
                  "items": {
                    "type": "object",
                    "required": ["file", "action"],
                    "properties": {
                      "file": {
                        "type": "string",
                        "description": "Relative path from repo root"
                      },
                      "action": {
                        "type": "string",
                        "enum": ["add", "modify", "delete"],
                        "description": "What the plan proposes for this file"
                      },
                      "summary": {
                        "type": "string",
                        "description": "One-line description of the change"
                      },
                      "phase": {
                        "type": "integer",
                        "description": "Which implementation phase introduces this change"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
```

**Example instance:**

```json
{
  "layers": [
    {
      "name": "Apps",
      "dependsOn": ["Features", "Services", "SDKs"],
      "modules": [
        {
          "name": "AIDevToolsKitMac",
          "changes": [
            {
              "file": "AIDevToolsKit/Sources/Apps/AIDevToolsKitMac/Views/ArchitectureView.swift",
              "action": "add",
              "summary": "New view rendering the architecture diagram",
              "phase": 5
            }
          ]
        },
        {
          "name": "AIDevToolsKitCLI",
          "changes": []
        }
      ]
    },
    {
      "name": "Features",
      "dependsOn": ["Services", "SDKs"],
      "modules": [
        {
          "name": "PlanRunnerFeature",
          "changes": [
            {
              "file": "AIDevToolsKit/Sources/Features/PlanRunnerFeature/usecases/GeneratePlanUseCase.swift",
              "action": "modify",
              "summary": "Add architecture JSON generation to Phase 3 prompt",
              "phase": 4
            }
          ]
        }
      ]
    },
    {
      "name": "Services",
      "dependsOn": ["SDKs"],
      "modules": []
    },
    {
      "name": "SDKs",
      "dependsOn": [],
      "modules": [
        {
          "name": "RepositorySDK",
          "changes": []
        }
      ]
    }
  ]
}
```

**Design decisions:**
- `changes` array is empty (not omitted) for unaffected modules — the app needs unaffected modules to render the full architecture
- `phase` field ties each change back to the plan's phase numbering, enabling the UI to highlight changes per-phase
- `dependsOn` is denormalized from ARCHITECTURE.md into the JSON so the app can draw dependency arrows without parsing markdown
- Modules with no changes still appear so the diagram always shows the complete architecture

---

### 3. LLM Integration — How the JSON Gets Produced

**When:** During Phase 3 ("Plan the Implementation") of plan execution. Phase 3 already reads the plan, understands the request, and generates implementation phases 4–N. At this same step, it also produces the architecture JSON.

**How:** The Phase 3 execution prompt is extended to include:

1. Read the repository's `ARCHITECTURE.md` (already passed via `architectureDocs`)
2. After generating the implementation phases, produce a JSON file conforming to the schema above
3. For each file that would be added, modified, or deleted across all generated phases, determine which module it belongs to by matching file paths against the module structure
4. Write the JSON to `{proposed-dir}/{plan-name}-architecture.json`

**Path mapping heuristic:** The LLM maps file paths to modules using the directory structure convention. For this project: `AIDevToolsKit/Sources/{Layer}/{ModuleName}/...` → module `ModuleName` in layer `{Layer}`. Each repo's ARCHITECTURE.md implicitly defines this mapping through its module listing. The LLM uses the file path and the module names to make the association.

**Prompt addition for Phase 3** (conceptual — not the final implementation):

```
After generating implementation phases, also produce an architecture diagram JSON file.

Read the repository's ARCHITECTURE.md to understand the layers and modules.
For every file you plan to add, modify, or delete across all implementation phases,
map it to the appropriate module and layer.

Write the JSON to: {proposed-dir}/{plan-name}-architecture.json

The JSON must conform to this schema: [schema]

Include ALL layers and modules from ARCHITECTURE.md, even those with no changes.
```

---

### 4. File Storage Convention

- **Location:** Same directory as the plan markdown (`docs/proposed/` or `docs/completed/`)
- **Naming:** `{plan-filename-without-extension}-architecture.json`
  - Example: plan `2026-03-22-h-new-feature.md` → `2026-03-22-h-new-feature-architecture.json`
- **Lifecycle:** The JSON file moves alongside the plan when it transitions from `proposed/` to `completed/`
- **Optional:** If a repo has no `ARCHITECTURE.md`, no JSON is produced and the UI gracefully omits the diagram

This means `moveToCompleted()` in `ExecutePlanUseCase` needs to also move the `-architecture.json` file when present.

---

### 5. File-to-Layer Mapping Strategy

The LLM determines which module a file belongs to by:

1. Reading ARCHITECTURE.md to get the list of layers and module names
2. For each planned file change, matching the file path against known module paths
3. Using directory structure conventions (e.g., `Sources/{Layer}/{Module}/`) to resolve ambiguity
4. If a file doesn't clearly map to any module (e.g., root-level config files), it is omitted from the architecture JSON — the diagram only shows architectural modules

**Edge cases:**
- **New modules:** If a plan creates a new module, the LLM includes it in the JSON under the appropriate layer, noting it as new via all-`add` changes. The ARCHITECTURE.md would be updated separately (not by the LLM during plan execution)
- **Cross-module changes:** A single phase may touch files in multiple modules — each file is listed under its respective module with the same `phase` number
- **Test files:** Tests typically live alongside or near their module. They map to the same module they test

---

### 6. Swift App Rendering Approach

The Swift app owns all visual decisions. Given the JSON, it renders:

- **Horizontal bands** for each layer, stacked top-to-bottom (Apps at top, SDKs at bottom)
- **Rounded rectangles** for each module within a layer, arranged horizontally
- **Color coding:**
  - Unaffected modules: neutral/gray
  - Affected modules: accent color (e.g., blue) with intensity proportional to number of changes
  - Within affected modules: add = green, modify = yellow, delete = red (for change detail)
- **Dependency arrows:** Downward arrows between layer bands showing allowed dependency directions
- **Interaction:** Tapping a module shows its change list (file, action, summary, phase)

The app reads `{plan-name}-architecture.json` from the same directory as the plan. If the file doesn't exist, the architecture section is hidden.

This rendering is designed for Phase 2 and is listed here only to confirm the JSON schema supports it.

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
