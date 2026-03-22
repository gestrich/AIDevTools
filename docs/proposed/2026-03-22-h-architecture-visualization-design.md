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

## - [x] Phase 2: Graphical UI Integration

Design the UI for viewing the architecture diagram within the planning detail:

- Render the architecture diagram from JSON in the plan detail view (not SVG — native SwiftUI)
- Allow the user to select a layer/module and see which proposed changes affect it
- Consider how this integrates alongside the existing phase checklist in the plan detail view

---

### 1. Placement in PlanDetailView

The current `PlanDetailView` body layout (top to bottom):

```
headerBar
errorBanner (conditional)
ScrollView {
    phaseSection
    outputPanel (conditional, during execution)
    completionBanner (conditional)
    Divider
    Markdown(planContent)
}
```

The architecture diagram appears **between the phase section and the markdown content**, as a collapsible section. It provides a visual "where do changes land?" summary before diving into the full plan text.

**Updated layout:**

```
headerBar
errorBanner (conditional)
ScrollView {
    phaseSection
    architectureSection (conditional — only when JSON exists)
    outputPanel (conditional, during execution)
    completionBanner (conditional)
    Divider
    Markdown(planContent)
}
```

The architecture section is conditional: it only renders when a `-architecture.json` file exists alongside the plan. The `loadPlan()` method is extended to also attempt loading the architecture JSON.

---

### 2. Architecture Diagram View

The diagram is rendered entirely in SwiftUI — no WebView, SVG, or external rendering.

**Structure:**

```
ArchitectureDiagramView
├── VStack (layer bands, top-to-bottom)
│   ├── LayerBandView("Apps")
│   │   ├── HStack (modules, evenly spaced)
│   │   │   ├── ModuleCardView("AIDevToolsKitMac", affected: true, changeCount: 1)
│   │   │   └── ModuleCardView("AIDevToolsKitCLI", affected: false, changeCount: 0)
│   │   └── layer label on the left edge
│   ├── DependencyArrow (downward)
│   ├── LayerBandView("Features")
│   │   └── ...
│   ├── DependencyArrow (downward)
│   ├── LayerBandView("Services")
│   │   └── ...
│   ├── DependencyArrow (downward)
│   └── LayerBandView("SDKs")
│       └── ...
└── ModuleDetailPanel (conditional — when a module is selected)
```

**LayerBandView:**
- Full-width horizontal band with a subtle background tint
- Layer name label on the leading edge, vertically centered
- Modules arranged in a flexible horizontal layout (wrapping if needed via `FlowLayout` or `LazyVGrid`)
- Light border to separate layers visually

**ModuleCardView:**
- Rounded rectangle (`RoundedRectangle(cornerRadius: 8)`)
- Module name centered inside
- **Unaffected:** `.secondary` foreground, `.quaternary` background
- **Affected:** Accent-colored border, badge showing change count in top-trailing corner
- Tap gesture sets `selectedModule` state
- Selected state: thicker border + slight scale effect

**DependencyArrow:**
- Simple downward chevron or arrow between layer bands
- Drawn with `Image(systemName: "chevron.down")` centered, `.tertiary` foreground
- Minimal — just indicates "depends on below"

---

### 3. Color Coding

| State | Background | Border | Text |
|-------|-----------|--------|------|
| Unaffected module | `.fill.quaternary` | none | `.secondary` |
| Affected module (selected) | `.tint.opacity(0.15)` | `.tint` 2pt | `.primary` |
| Affected module (not selected) | `.tint.opacity(0.08)` | `.tint.opacity(0.5)` 1pt | `.primary` |
| Layer band background | `.fill.quinary` | — | — |

Change action colors appear only in the detail panel:
- **add:** `.green`
- **modify:** `.yellow` / `.orange`
- **delete:** `.red`

---

### 4. Module Selection and Detail Panel

**State:** `@State private var selectedModule: ModuleSelection?` where `ModuleSelection` is a struct with `layerName` and `moduleName`.

**Behavior:**
- Tapping an affected module selects it; tapping again deselects
- Tapping an unaffected module does nothing (no changes to show)
- Only one module can be selected at a time

**ModuleDetailPanel** appears below the diagram (inside the same `VStack`) when a module is selected:

```
┌─────────────────────────────────────────────┐
│  PlanRunnerFeature                     ✕    │
│─────────────────────────────────────────────│
│  ● add   usecases/NewUseCase.swift   Ph.5  │
│  ● mod   usecases/GeneratePlan...    Ph.4  │
│  ● mod   services/ClaudeRespo...     Ph.4  │
└─────────────────────────────────────────────┘
```

- Header: module name + close button
- Each row: colored dot (action), file path (truncated, tooltip for full path), phase number
- Rows sorted by phase number, then alphabetically by file path
- Tapping a row could eventually open the file, but for v1 it's display-only

---

### 5. Data Loading

**In `loadPlan()`:** After loading the markdown, also attempt to load the architecture JSON:

```swift
let architectureURL = plan.planURL
    .deletingPathExtension()
    .appendingPathExtension("architecture.json")
// Note: this doesn't work — need string manipulation instead

// Correct approach:
let planName = plan.planURL.deletingPathExtension().lastPathComponent
let architectureURL = plan.planURL
    .deletingLastPathComponent()
    .appendingPathComponent("\(planName)-architecture.json")
```

If the file exists, decode it into the `ArchitectureDiagram` model (a Swift `Codable` struct mirroring the JSON schema). If it doesn't exist, `architectureDiagram` remains `nil` and the section is hidden.

**New state property:**
```swift
@State private var architectureDiagram: ArchitectureDiagram?
```

---

### 6. Collapsibility

The architecture section uses a `DisclosureGroup` so it can be collapsed:

```swift
DisclosureGroup("Architecture", isExpanded: $isArchitectureExpanded) {
    ArchitectureDiagramView(
        diagram: diagram,
        selectedModule: $selectedModule
    )
}
```

Default: expanded on first load, remembering toggle state for the session.

---

### 7. Responsive Layout

- **Narrow windows:** Modules wrap to multiple rows within a layer band. The `FlowLayout` or `LazyVGrid` handles this automatically.
- **Wide windows:** Modules spread horizontally with consistent spacing.
- **Module cards:** Fixed minimum width (~100pt), flexible max. Text truncates with `lineLimit(1)`.
- **Overall diagram:** No fixed height — it grows with the number of layers/modules. The parent `ScrollView` handles overflow.

---

### 8. View Decomposition

New files needed (all in `AIDevToolsKitMac/Views/`):

| View | Responsibility |
|------|---------------|
| `ArchitectureDiagramView` | Top-level container: layer stack + detail panel |
| `LayerBandView` | Single layer: label + module cards |
| `ModuleCardView` | Single module: name, badge, tap target |
| `ModuleDetailPanel` | Selected module's change list |

Model file (in `PlanRunnerFeature` or `PlanRunnerService`):

| Model | Responsibility |
|-------|---------------|
| `ArchitectureDiagram` | `Codable` struct matching the JSON schema from Phase 1 |

Keeping the views small and focused follows the existing pattern in the codebase where `PlanDetailView` is already ~280 lines.

## Later Steps (Not Yet Scoped)

- Violation detection (e.g., "this looks like business logic but it's in the UI layer")
- Architectural principles/rules per layer and annotation of which principle justifies a placement
- "Why here?" interactive justification from AI
- Refactoring detection, violation alerts

## - [x] Phase 3: Validation

- Review the design document with a real plan to verify the model is expressive enough
- Walk through a sample plan and manually annotate where changes would land — confirm the model captures it
- Identify any gaps or missing concepts before implementation begins

---

### Test Case: `2026-03-21-a-unified-app-rearchitecture.md`

This 8-phase plan unified two separate repository models, migrated both Evals and Plan Runner to a shared `RepositorySDK`, generalized the Mac app navigation, and added a Plan Runner UI. It touched every architectural layer.

**Mapping each phase's file changes to the architecture:**

| Phase | Layer | Module | Files | Action |
|-------|-------|--------|-------|--------|
| 1 | SDKs | RepositorySDK | `RepositoryInfo.swift`, `RepositoryStore.swift`, `RepositoryStoreConfiguration.swift` | add |
| 1 | (root) | — | `Package.swift` | modify |
| 2 | Services | SkillService | `RepositoryConfiguration.swift`, `RepositoryConfigurationStore.swift`, `SkillServiceConfiguration.swift` | delete |
| 2 | Features | SkillBrowserFeature | `LoadRepositoriesUseCase.swift`, `AddRepositoryUseCase.swift`, etc. | modify |
| 2 | Services | EvalService | Various files updated for new types | modify |
| 2 | Apps | AIDevToolsKitCLI | `ReposCommand.swift`, `SkillsCommand.swift` | modify |
| 3 | Services | PlanRunnerService | `Repository.swift`, `ReposConfig.swift` | delete |
| 3 | Features | PlanRunnerFeature | `GeneratePlanUseCase.swift`, `ExecutePlanUseCase.swift`, `ClaudeResponseModels.swift` | modify |
| 3 | Apps | AIDevToolsKitCLI | `PlanRunnerPlanCommand.swift`, `PlanRunnerExecuteCommand.swift` | modify |
| 4 | — | — | (external data files only — no code changes) | — |
| 5 | Apps | AIDevToolsKitMac | `SkillBrowserView.swift` → `WorkspaceView.swift`, `SkillBrowserModel.swift` → `WorkspaceModel.swift`, `AIDevToolsApp.swift` | modify |
| 6 | Apps | AIDevToolsKitMac | `PlanDetailView.swift`, `PlanListView.swift`, `PlanRunnerModel.swift` | add |
| 7 | (root) | — | `Package.swift` | modify |
| 8 | — | — | (validation only — no code changes) | — |

**Sample architecture JSON this plan would produce:**

```json
{
  "layers": [
    {
      "name": "Apps",
      "dependsOn": ["Features", "Services", "SDKs"],
      "modules": [
        {
          "name": "AIDevToolsKitCLI",
          "changes": [
            { "file": "Sources/Apps/AIDevToolsKitCLI/ReposCommand.swift", "action": "modify", "summary": "Use RepositoryStore instead of old config types", "phase": 2 },
            { "file": "Sources/Apps/AIDevToolsKitCLI/SkillsCommand.swift", "action": "modify", "summary": "Use RepositoryInfo", "phase": 2 },
            { "file": "Sources/Apps/AIDevToolsKitCLI/PlanRunnerPlanCommand.swift", "action": "modify", "summary": "Load repos from RepositoryStore", "phase": 3 },
            { "file": "Sources/Apps/AIDevToolsKitCLI/PlanRunnerExecuteCommand.swift", "action": "modify", "summary": "Load repos from RepositoryStore", "phase": 3 }
          ]
        },
        {
          "name": "AIDevToolsKitMac",
          "changes": [
            { "file": "Sources/Apps/AIDevToolsKitMac/Views/WorkspaceView.swift", "action": "modify", "summary": "Rename from SkillBrowserView, generalize navigation", "phase": 5 },
            { "file": "Sources/Apps/AIDevToolsKitMac/Models/WorkspaceModel.swift", "action": "modify", "summary": "Rename from SkillBrowserModel", "phase": 5 },
            { "file": "Sources/Apps/AIDevToolsKitMac/AIDevToolsApp.swift", "action": "modify", "summary": "Use new model/view names", "phase": 5 },
            { "file": "Sources/Apps/AIDevToolsKitMac/Views/PlanDetailView.swift", "action": "add", "summary": "Plan detail with phase checklist and execution", "phase": 6 },
            { "file": "Sources/Apps/AIDevToolsKitMac/Views/PlanListView.swift", "action": "add", "summary": "Plan list for selected repository", "phase": 6 },
            { "file": "Sources/Apps/AIDevToolsKitMac/Models/PlanRunnerModel.swift", "action": "add", "summary": "Observable model for plan state", "phase": 6 }
          ]
        }
      ]
    },
    {
      "name": "Features",
      "dependsOn": ["Services", "SDKs"],
      "modules": [
        { "name": "AnthropicChatFeature", "changes": [] },
        { "name": "ClaudeCodeChatFeature", "changes": [] },
        { "name": "EvalFeature", "changes": [] },
        {
          "name": "PlanRunnerFeature",
          "changes": [
            { "file": "Sources/Features/PlanRunnerFeature/usecases/GeneratePlanUseCase.swift", "action": "modify", "summary": "Accept RepositoryInfo instead of Repository", "phase": 3 },
            { "file": "Sources/Features/PlanRunnerFeature/usecases/ExecutePlanUseCase.swift", "action": "modify", "summary": "Accept RepositoryInfo instead of Repository", "phase": 3 },
            { "file": "Sources/Features/PlanRunnerFeature/services/ClaudeResponseModels.swift", "action": "modify", "summary": "Update RepoMatch to use shared ID type", "phase": 3 }
          ]
        },
        {
          "name": "SkillBrowserFeature",
          "changes": [
            { "file": "Sources/Features/SkillBrowserFeature/usecases/LoadRepositoriesUseCase.swift", "action": "modify", "summary": "Use RepositoryInfo and RepositoryStore", "phase": 2 },
            { "file": "Sources/Features/SkillBrowserFeature/usecases/AddRepositoryUseCase.swift", "action": "modify", "summary": "Use RepositoryInfo and RepositoryStore", "phase": 2 }
          ]
        }
      ]
    },
    {
      "name": "Services",
      "dependsOn": ["SDKs"],
      "modules": [
        { "name": "AnthropicChatService", "changes": [] },
        { "name": "ClaudeCodeChatService", "changes": [] },
        {
          "name": "EvalService",
          "changes": [
            { "file": "Sources/Services/EvalService/EvalRepoSettings.swift", "action": "add", "summary": "Eval-specific repo settings (casesDirectory)", "phase": 2 },
            { "file": "Sources/Services/EvalService/EvalRepoSettingsStore.swift", "action": "add", "summary": "Persistence for eval-specific settings", "phase": 2 }
          ]
        },
        {
          "name": "PlanRunnerService",
          "changes": [
            { "file": "Sources/Services/PlanRunnerService/Models/Repository.swift", "action": "delete", "summary": "Replaced by RepositoryInfo in RepositorySDK", "phase": 3 },
            { "file": "Sources/Services/PlanRunnerService/Models/ReposConfig.swift", "action": "delete", "summary": "Replaced by RepositoryStore in RepositorySDK", "phase": 3 }
          ]
        },
        {
          "name": "SkillService",
          "changes": [
            { "file": "Sources/Services/SkillService/RepositoryConfiguration.swift", "action": "delete", "summary": "Replaced by RepositoryInfo", "phase": 2 },
            { "file": "Sources/Services/SkillService/RepositoryConfigurationStore.swift", "action": "delete", "summary": "Replaced by RepositoryStore", "phase": 2 },
            { "file": "Sources/Services/SkillService/SkillServiceConfiguration.swift", "action": "delete", "summary": "Replaced by RepositoryStoreConfiguration", "phase": 2 }
          ]
        }
      ]
    },
    {
      "name": "SDKs",
      "dependsOn": [],
      "modules": [
        { "name": "AnthropicSDK", "changes": [] },
        { "name": "ClaudeCLISDK", "changes": [] },
        { "name": "ClaudePythonSDK", "changes": [] },
        { "name": "CodexCLISDK", "changes": [] },
        { "name": "ConcurrencySDK", "changes": [] },
        { "name": "EnvironmentSDK", "changes": [] },
        { "name": "EvalSDK", "changes": [] },
        { "name": "GitSDK", "changes": [] },
        { "name": "LoggingSDK", "changes": [] },
        {
          "name": "RepositorySDK",
          "changes": [
            { "file": "Sources/SDKs/RepositorySDK/RepositoryInfo.swift", "action": "add", "summary": "Unified repository model", "phase": 1 },
            { "file": "Sources/SDKs/RepositorySDK/RepositoryStore.swift", "action": "add", "summary": "Unified persistence", "phase": 1 },
            { "file": "Sources/SDKs/RepositorySDK/RepositoryStoreConfiguration.swift", "action": "add", "summary": "Data path configuration", "phase": 1 }
          ]
        },
        { "name": "SkillScannerSDK", "changes": [] }
      ]
    }
  ]
}
```

### Findings

**The model works.** The JSON above captures the plan's changes across all four layers, 16 modules, and 6 implementation phases. Every file change has a clear module mapping and the `phase` field correctly traces changes back to plan phases.

**Gaps identified:**

1. **Root-level files (e.g., `Package.swift`)** — The model has no place for files that don't belong to any module. `Package.swift` changes are common in plans that add/remove targets. **Severity: Low.** These changes are structural (adding a target line) rather than architectural. The diagram is about where code lives, not build config. **No schema change needed** — document this as an intentional exclusion.

2. **File renames** — Phase 5 renamed `SkillBrowserView` → `WorkspaceView`. The schema has `add`/`modify`/`delete` but not `rename`. A rename can be approximated as `modify` (same file, new name) but loses the rename semantic. **Severity: Low.** Renames are infrequent and the approximation is acceptable for v1. A future `"rename"` action with an `oldFile` field could be added if needed.

3. **Phases with no code changes** — Phases 4 (manual data migration) and 8 (validation) produce no entries in the JSON. This is correct — the diagram shows code architecture, not every phase's activity.

4. **Test file mapping** — Tests in `Tests/SDKs/RepositorySDKTests/` map to `RepositorySDK`. This works because the naming convention mirrors the source module. The LLM should be instructed to map test files to the module they test, not create separate test "modules."

5. **Layer rule exceptions** — `EvalSDK` depends on `EvalService` (an SDK depending on a Service), violating the standard layer rule. The model captures layer-level `dependsOn` rules, not module-level exceptions. **Severity: Low for v1.** The "Later Steps" violation detection feature would need module-level dependency data, but that's out of scope for this design.

### Conclusion

The data model is expressive enough for its intended purpose. The five gaps identified are all low severity and don't warrant schema changes for v1. The sample JSON validates that a real, complex plan maps cleanly onto the architecture diagram model.

---

## Implementation Phases

## - [ ] Phase 4: ArchitectureDiagram Codable Model

**Skills to read**: `swift-testing`

Create the `ArchitectureDiagram` Codable model in `PlanRunnerService` (Services layer) — this is a data model like `PlanEntry` and `PlanRepoSettings`, with no business logic.

- Create `Sources/Services/PlanRunnerService/ArchitectureDiagram.swift` with structs matching the JSON schema from Phase 1:
  - `ArchitectureDiagram` — top-level, contains `layers: [ArchitectureLayer]`
  - `ArchitectureLayer` — `name`, `dependsOn`, `modules: [ArchitectureModule]`
  - `ArchitectureModule` — `name`, `changes: [ArchitectureChange]`
  - `ArchitectureChange` — `file`, `action` (enum: add/modify/delete), `summary` (optional), `phase` (optional)
  - All types: `Codable`, `Sendable`, `Equatable`
- Add computed helpers:
  - `ArchitectureModule.isAffected: Bool` — `!changes.isEmpty`
  - `ArchitectureDiagram.affectedModuleCount: Int`
- Write unit tests in `Tests/Services/PlanRunnerServiceTests/ArchitectureDiagramTests.swift`:
  - Round-trip encode/decode from sample JSON (use the example from Phase 1)
  - Decode JSON with empty `changes` arrays
  - Verify `isAffected` computed property
  - Verify `action` enum decodes all three cases
- Ensure `swift build` passes

## - [ ] Phase 5: Create ARCHITECTURE.md for This Repository

Create the first real `ARCHITECTURE.md` for the AIDevTools project, following the convention defined in Phase 1. This serves as both a reference example and enables architecture visualization for this repo's own plans.

- Create `AIDevToolsKit/ARCHITECTURE.md` using the actual module structure from Package.swift
- Include all four layers: Apps (2 modules), Features (5 modules), Services (5 modules), SDKs (11 modules)
- Include `Depends on:` lines and `## Dependency Rules` summary
- Verify the `architectureDocs` field on the AIDevTools repository configuration includes this file path (or note it needs to be added manually via the repos settings)

## - [ ] Phase 6: Update Plan Generation to Produce Architecture JSON

Modify `GeneratePlanUseCase` so that the Phase 3 template instructs the LLM to also produce an architecture JSON file when it generates implementation phases.

- In `GeneratePlanUseCase.generatePlan()`, update the Phase 3 description in the prompt to include:
  - Read the repository's ARCHITECTURE.md (if present in `architectureDocs`)
  - After generating implementation phases, also write `{proposed-dir}/{plan-name}-architecture.json`
  - The JSON must include ALL layers and modules from ARCHITECTURE.md, with `changes` populated for affected modules
  - Provide the JSON schema inline in the prompt
- The instruction is embedded in the plan markdown — `ExecutePlanUseCase` does NOT need changes. When Claude executes Phase 3, it reads the plan text and follows the embedded instructions.
- If no ARCHITECTURE.md is listed in `architectureDocs`, the Phase 3 text should skip the architecture JSON instruction (conditional inclusion in the template)

## - [ ] Phase 7: SwiftUI Architecture Diagram Views

**Skills to read**: `swift-testing`

Create the four SwiftUI views from the Phase 2 design in `Sources/Apps/AIDevToolsKitMac/Views/`:

- `ArchitectureDiagramView.swift` — Top-level container:
  - Takes `ArchitectureDiagram` and `Binding<ModuleSelection?>`
  - `VStack` of `LayerBandView`s with chevron separators between layers
  - `ModuleDetailPanel` below the diagram when a module is selected
- `LayerBandView.swift` — Single layer band:
  - Layer name label on leading edge
  - Horizontal flow of `ModuleCardView`s (use `LazyVGrid` or wrapping `HStack`)
  - Subtle background tint
- `ModuleCardView.swift` — Single module card:
  - Rounded rectangle with module name
  - Unaffected: gray/secondary styling
  - Affected: accent border + change count badge
  - Tap gesture for selection (only on affected modules)
- `ModuleDetailPanel.swift` — Change list for selected module:
  - Header with module name + close button
  - Rows: colored dot (action), file path, phase number
  - Sorted by phase then file path alphabetically
- Create `ModuleSelection.swift` (can be in the same file as `ArchitectureDiagramView` or separate) — simple struct with `layerName` and `moduleName`

## - [ ] Phase 8: Integrate into PlanDetailView and Plan Lifecycle

Wire the architecture diagram into the existing plan detail view and update the plan file lifecycle.

- In `PlanDetailView`:
  - Add `@State private var architectureDiagram: ArchitectureDiagram?`
  - Add `@State private var selectedModule: ModuleSelection?`
  - Add `@State private var isArchitectureExpanded = true`
  - In `loadPlan()`, after loading markdown, attempt to load `{plan-name}-architecture.json` from the same directory and decode it
  - Add architecture section (in a `DisclosureGroup`) between `phaseSection` and `outputPanel` in the body, conditional on `architectureDiagram != nil`
- In `ExecutePlanUseCase.moveToCompleted()`:
  - After moving the plan markdown, also move the `-architecture.json` file if it exists
- Add `import PlanRunnerService` if not already present (for `ArchitectureDiagram` type)

## - [ ] Phase 9: Validation

**Skills to read**: `swift-testing`

- Run `swift build` in AIDevToolsKit — verify clean compilation
- Run `swift test` — verify all existing tests still pass plus new `ArchitectureDiagramTests`
- Build and run the Mac app in Xcode:
  - Open a plan that does NOT have an architecture JSON — verify the architecture section is hidden and nothing is broken
  - Manually create a test `-architecture.json` file alongside a plan (using the sample JSON from Phase 3's validation) and verify:
    - The architecture diagram section appears
    - Layers render top-to-bottom
    - Affected modules show accent styling and badge
    - Tapping a module shows the detail panel
    - Collapsing/expanding the disclosure group works
  - Verify the plan still executes normally with the architecture section visible
