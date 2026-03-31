## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture — SDK/Feature/App placement, stateless value types |
| `swift-app-architecture:swift-swiftui` | SwiftUI patterns: @Observable models, HSplitView, drag-to-reorder, sheet/popover patterns |

## Background

The unified pipeline model (`PipelineSDK`, `PipelineFeature`) established the execution primitives — `CodeChangeStep`, `ReviewStep`, `CreatePRStep` — and a `PipelineSource` protocol for loading and persisting pipelines. Today the only pipeline source is `MarkdownPipelineSource`, which has a key limitation: markdown can only store step *descriptions*. The `prompt`, `skills`, `ReviewScope`, and PR templates are lost — they're derived from the description string at parse time.

The goal is a **graphical pipeline editor** where you can visually build a pipeline step-by-step, configure each step's full properties, reorder steps, and save it. This should become the authoring foundation for both Plans (currently markdown phases) and Claude Chain (currently markdown tasks).

### Key design decisions

**Storage: JSON pipeline documents**

A richer source format is needed to store all step properties. A `JSONPipelineSource` backed by a `.pipeline` JSON file is the right choice:
- Round-trips all step types and their full configuration
- Machine-writable (editor saves it) and machine-readable (executor loads it)
- Still human-readable/diffable
- `MarkdownPipelineSource` continues to work for existing files (execution path unchanged)
- New pipelines created in the editor are `.pipeline` JSON files

**Step palette**

The three step types that exist today become the palette in the editor:

| Step Type | What you configure |
|-----------|-------------------|
| `CodeChangeStep` | Description, AI prompt, skills to read |
| `ReviewStep` | Description, scope (all since last review / last N / specific steps), AI prompt |
| `CreatePRStep` | Description, title template, body template, label |

**Relationship to Plans and ClaudeChain**

Near-term: graphical editor is a new authoring path that produces `.pipeline` JSON files, runnable by `ExecutePipelineUseCase`. Plans and ClaudeChain continue to use markdown.

Longer-term vision: Plans tab becomes a Pipelines tab. Creating a new plan opens the graphical editor instead of generating a markdown file. ClaudeChain specs become importable pipelines. Markdown remains as an import/legacy path.

This plan covers building the editor and JSON source. Migration of Plans/ClaudeChain is out of scope here.

## Phases

## - [ ] Phase 1: JSON pipeline storage (`PipelineSDK`)

**Skills to read**: `swift-app-architecture:swift-architecture`

Add a `Codable` serialization layer to `PipelineSDK` and a `JSONPipelineSource` implementation.

**`PipelineDocument`** — Codable envelope that serializes a `Pipeline`:

```swift
public struct PipelineDocument: Codable, Sendable {
    public var id: String
    public var name: String
    public var steps: [PipelineStepRecord]
}
```

**`PipelineStepRecord`** — discriminated union for all step types:

```swift
public enum PipelineStepRecord: Codable, Sendable {
    case codeChange(CodeChangeStepRecord)
    case review(ReviewStepRecord)
    case createPR(CreatePRStepRecord)
}
```

Each `*Record` type is a `Codable` struct matching the fields of the corresponding `PipelineStep` concrete type. `ReviewScope` needs explicit `Codable` conformance (associated values).

**`JSONPipelineSource: PipelineSource`**:
- `load()` — decode `PipelineDocument` from file, convert records → step instances
- `markStepCompleted(_:)` — load document, update matching record's `isCompleted`, re-encode
- `appendSteps(_:)` — load document, append new records, re-encode
- `save(_:)` — encode and write full document (used by the editor)

File extension: `.pipeline` (JSON under the hood).

**Files to create:**
- `PipelineSDK/PipelineDocument.swift`
- `PipelineSDK/PipelineStepRecord.swift`
- `PipelineSDK/JSONPipelineSource.swift`

## - [ ] Phase 2: `PipelineEditorModel` (App layer)

**Skills to read**: `swift-app-architecture:swift-architecture`, `swift-app-architecture:swift-swiftui`

An `@Observable` model that owns the in-memory pipeline being edited.

```swift
@Observable
final class PipelineEditorModel {
    var pipeline: Pipeline
    var selectedStepID: String?
    var isDirty: Bool

    func addStep(_ step: any PipelineStep)
    func removeStep(id: String)
    func moveStep(from: Int, to: Int)
    func updateStep(_ step: any PipelineStep)
    func save() async throws   // writes via JSONPipelineSource
    func load(from url: URL) async throws
}
```

`isDirty` tracks unsaved changes. `save()` encodes the current `pipeline` to a `PipelineDocument` and writes it. Model lives in `AIDevToolsKitMac`.

**Files to create:**
- `AIDevToolsKitMac/Models/PipelineEditorModel.swift`

## - [ ] Phase 3: Step card views

**Skills to read**: `swift-app-architecture:swift-swiftui`

A card view for each step type, used in the ordered step list. Each card shows:
- Step type badge (icon + label: "Code Change", "Review", "Create PR")
- Description (truncated to one line)
- Completion indicator (checkbox or checkmark)
- Selection highlight

```swift
struct PipelineStepCardView: View {
    let step: any PipelineStep
    let isSelected: Bool
}
```

Type dispatch inside `PipelineStepCardView` drives the badge style and icon. Cards support drag-to-reorder via SwiftUI's `.onMove` modifier on the `List`.

**Files to create:**
- `AIDevToolsKitMac/Views/PipelineEditor/PipelineStepCardView.swift`

## - [ ] Phase 4: Step editor panel

**Skills to read**: `swift-app-architecture:swift-swiftui`

A detail panel that edits the selected step's full configuration. Three type-specific editors:

**`CodeChangeStepEditorView`**
- `TextField` for description
- `TextEditor` for prompt (multiline)
- Tag-style skills input (comma-separated, or a simple `TextField`)

**`ReviewStepEditorView`**
- `TextField` for description
- `Picker` for scope: "All since last review", "Last N steps", "Specific steps"
  - When "Last N": a `Stepper` for N
  - When "Specific steps": multi-select from step IDs in the pipeline
- `TextEditor` for prompt

**`CreatePRStepEditorView`**
- `TextField` for description
- `TextField` for title template (with `{{branch}}` placeholder hint)
- `TextEditor` for body template
- `TextField` for label (optional)

All editors bind to a copy of the step. On change, call `model.updateStep(_:)`.

**Files to create:**
- `AIDevToolsKitMac/Views/PipelineEditor/CodeChangeStepEditorView.swift`
- `AIDevToolsKitMac/Views/PipelineEditor/ReviewStepEditorView.swift`
- `AIDevToolsKitMac/Views/PipelineEditor/CreatePRStepEditorView.swift`

## - [ ] Phase 5: `PipelineEditorView` (main canvas)

**Skills to read**: `swift-app-architecture:swift-swiftui`

The top-level editor view composing the step list and detail panel.

Layout: `HSplitView` with the ordered step list on the left and the step editor on the right.

```
┌─────────────────────────────────────────────────────┐
│ Pipeline name (editable)          [Run] [Save]       │
├───────────────────────┬─────────────────────────────┤
│ + Add Step ▾          │ Step Editor                  │
│                       │                              │
│ ☐ Code Change: ...    │  [CodeChangeStepEditorView]  │
│ ☐ Code Change: ...    │                              │
│ ☐ Review: ...         │                              │
│ ☐ Create PR           │                              │
└───────────────────────┴─────────────────────────────┘
```

- **"+ Add Step"** button: popover with three options (Code Change, Review, Create PR). Each option inserts a new step with empty defaults and selects it.
- **Drag handles** on cards for reordering.
- **Delete** via swipe-to-delete or a toolbar button when a step is selected.
- **"Save"** calls `model.save()`, clears `isDirty`.
- **"Run"** (stretch): kicks off `ExecutePipelineUseCase` with `JSONPipelineSource` — wires to the existing execution infrastructure.

**Files to create:**
- `AIDevToolsKitMac/Views/PipelineEditor/PipelineEditorView.swift`

## - [ ] Phase 6: Workspace integration

**Skills to read**: `swift-app-architecture:swift-swiftui`

Add pipeline editing to the workspace so it's reachable.

**Option A (minimal):** A "New Pipeline" button in the existing Plans tab that opens a sheet with `PipelineEditorView` for creating a new `.pipeline` file. Plans tab continues to list markdown plans and shows the editor for newly authored pipelines.

**Option B (new tab):** A dedicated "Pipelines" tab in `WorkspaceView` alongside Plans, ClaudeChain, etc. Shows a list of `.pipeline` files in the repo alongside the editor. This is the foundation for eventually replacing Plans/ClaudeChain.

Use **Option A** for this plan (lower scope). Option B is the longer-term goal and can be a follow-on plan.

A `PipelineListModel` (or extend `MarkdownPlannerModel`) discovers `.pipeline` files in the repo and opens them in `PipelineEditorView`.

**Files to modify:**
- `AIDevToolsKitMac/Views/PlansContainer.swift` — add "New Pipeline" button and listing for `.pipeline` files

## - [ ] Phase 7: CLI integration

**Skills to read**: `swift-app-architecture:swift-architecture`

Add pipeline commands to the main CLI target so `.pipeline` JSON files are runnable without the Mac app.

```
ai-dev-tools pipeline run <path>      # execute a .pipeline file via ExecutePipelineUseCase
ai-dev-tools pipeline list [dir]      # list .pipeline files in a directory (default: cwd)
ai-dev-tools pipeline inspect <path>  # print steps with completion status
```

- `run` loads the file via `JSONPipelineSource`, instantiates `ExecutePipelineUseCase` with the appropriate step handlers, and streams progress to stdout
- Incomplete steps only — already-completed steps (checked off in the JSON) are skipped, enabling resume after partial execution
- `inspect` and `list` require no AI execution — useful for scripting and debugging

This mirrors the existing `claude-chain` and `arch-planner` patterns already in the main CLI target.

**Files to modify:**
- Main CLI target — add `PipelineCommand` subcommand group with `run`, `list`, `inspect`

## - [ ] Phase 8: Validation

**Skills to read**: `swift-app-architecture:swift-architecture`

**Unit tests (PipelineSDK):**
- `JSONPipelineSource` round-trips all three step types (encode → decode → verify fields)
- `markStepCompleted` updates the correct record in the JSON file
- `appendSteps` adds records without corrupting existing ones
- `ReviewScope` encodes/decodes all cases including associated values

**Build verification:**
- `swift build` succeeds
- Existing `PipelineSDKTests` and `PipelineFeatureTests` still pass

**Manual smoke test:**
1. Open Plans tab → "New Pipeline" → editor opens with empty pipeline
2. Add a Code Change step → editor panel shows → fill in description and prompt → save → `.pipeline` file written to disk
3. Add a Review step after it → configure scope to "All since last review"
4. Add a Create PR step at the end
5. Reorder steps via drag → save → reload → order preserved
6. Delete a step → save → reload → step gone
7. Run the pipeline → execution uses `JSONPipelineSource` → steps execute sequentially
