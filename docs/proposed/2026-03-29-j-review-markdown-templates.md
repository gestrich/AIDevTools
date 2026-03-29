## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture — confirms where new UI and logic belong |
| `swift-app-architecture:swift-swiftui` | SwiftUI patterns: @Observable models, sheets, popovers |

## Background

The MarkdownPlanner runs plan phases sequentially, each in a fresh AI context. Each phase prompt includes the path to the plan markdown, so Claude reads the file and sees which phases are completed (marked `[x]`) and what was built. This means a review step appended at the end of a plan has full visibility into what was implemented — no git diff injection or session continuation needed.

The goal is a **review template system** using the same markdown format as plans:

- `docs/reviews/` holds reusable review template files
- Each file uses `## - [ ]` headings, one per review+fix instruction
- When creating or editing a plan, you can select one or more review files to append
- The selected steps are appended to the plan markdown as regular `## - [ ]` phases
- During execution they run as ordinary `CodeChangeStep`s — no new step types, no new executor logic

### Why this approach

- **No new infrastructure** — `MarkdownPipelineSource.appendSteps()` already handles appending steps
- **Reusable** — one `architecture-compliance.md` applies to any plan
- **Human-editable** — review criteria live in version-controlled markdown
- **Predictable** — each review step runs once, reads the plan for context, reviews and fixes in one shot

### Example review file (`docs/reviews/architecture-compliance.md`)

```markdown
## - [x] Review completed phases for architecture layer violations and fix any found

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Reviewed AppIPCSDK (SDKs layer — stateless `Sendable` struct, no app-specific imports) and AppIPCServer (Apps layer — `@MainActor final class`, imports only SDK types, no upward dependencies). Build is clean. No violations found.
## - [x] Check that no feature imports another feature directly and fix violations

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Searched all Feature source files for cross-feature `import` statements and audited Package.swift for feature-to-feature target dependencies. No violations found — each Feature depends only on Services, SDKs, and external packages. Build is clean.
## - [x] Verify all new types are in their correct SDK/Feature/Service/App layer and move any that aren't

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Reviewed all types introduced by the AppIPCSDK, AppIPCServer, and MCPCommand commits. `AppIPCClient`, `IPCRequest`, `IPCUIState`, and `IPCError` are stateless `Sendable` structs/enums in `SDKs/AppIPCSDK/` ✓. `AppIPCServer` is a `@MainActor final class` in `Apps/AIDevToolsKitMac/IPC/` ✓. `MCPCommand` is an `AsyncParsableCommand` in `Apps/AIDevToolsKitCLI/` ✓. `LoadPlansUseCase` is a `Sendable` struct in `Features/MarkdownPlannerFeature/usecases/` ✓. No violations found. Build is clean.
```

## Phases

## - [ ] Phase 1: `docs/reviews/` convention and sample files

**Skills to read**: `swift-app-architecture:swift-architecture`

Establish the directory and seed it with useful review templates.

Create `docs/reviews/` and add initial review files:

- `architecture-compliance.md` — layer violations, feature-to-feature imports, wrong-layer types
- `swift-testing.md` — test style, naming, use of `#expect` vs `XCTAssert`, async patterns
- `build-quality.md` — no warnings, no TODOs left in code, no commented-out code

Each file uses `## - [ ]` headings. No special syntax — just the same format as plan files.

**Files to create:**
- `docs/reviews/architecture-compliance.md`
- `docs/reviews/swift-testing.md`
- `docs/reviews/build-quality.md`

## - [ ] Phase 2: `ReviewTemplateService` (Service layer)

**Skills to read**: `swift-app-architecture:swift-architecture`

A lightweight service that discovers and loads review template files. Lives in the Service layer since it's stateless file I/O with no AI calls.

```swift
public struct ReviewTemplateService: Sendable {
    public let reviewsDirectory: URL

    public func availableTemplates() throws -> [ReviewTemplate]
    public func loadSteps(from template: ReviewTemplate) throws -> [String]
}

public struct ReviewTemplate: Sendable, Identifiable {
    public let id: String       // filename without extension
    public let name: String     // human-readable (filename sans extension, dashes → spaces)
    public let url: URL
}
```

`availableTemplates()` lists `.md` files in `reviewsDirectory` sorted alphabetically.
`loadSteps(from:)` parses `## - [ ]` and `## - [x]` lines and returns the descriptions.

This service takes a `reviewsDirectory` URL so it works for any directory, not just `docs/reviews/`.

**Files to create:**
- A new `ReviewTemplateService` file in an appropriate existing Service target (e.g., `MarkdownPlannerService` or a shared utility target)

## - [ ] Phase 3: Append logic in `MarkdownPlannerModel`

**Skills to read**: `swift-app-architecture:swift-architecture`

Add a method to `MarkdownPlannerModel` that appends review steps from a template to the selected plan.

```swift
func appendReviewTemplate(_ template: ReviewTemplate, to planURL: URL) async throws
```

Implementation:
1. Load step descriptions via `ReviewTemplateService.loadSteps(from:)`
2. Convert each description to a `CodeChangeStep` (id, description, isCompleted: false, prompt: description, skills: [], context: .empty)
3. Call `MarkdownPipelineSource(fileURL: planURL, format: .phase).appendSteps(steps)`

The model already owns the plan URL when a plan is selected — no new state needed.

**Files to modify:**
- `AIDevToolsKitMac/Models/MarkdownPlannerModel.swift`

## - [ ] Phase 4: UI — review picker in `PlansContainer` / `MarkdownPlannerDetailView`

**Skills to read**: `swift-app-architecture:swift-swiftui`

Add a way to select and append a review template from the UI. Two candidate placements:

- **On an existing plan** (detail view header bar): an "Append Review" button that shows a popover listing available templates. Selecting one calls `markdownPlannerModel.appendReviewTemplate(_:to:)` and dismisses.
- **At plan creation time** (generate sheet): a multi-select list of review templates shown in the generate sheet, applied after plan generation.

Implement the **detail view button** (simpler, more generally useful — works on any plan whether generated or handwritten).

The button is enabled when a plan is selected and not currently executing.

Popover contents:
- List of `ReviewTemplate`s from `ReviewTemplateService`
- Tap to append (single selection, immediate — no confirm step needed)
- Show a brief success indicator after appending

**Files to modify:**
- `AIDevToolsKitMac/Views/MarkdownPlannerDetailView.swift`

## - [ ] Phase 5: Validation

**Skills to read**: `swift-app-architecture:swift-architecture`

**Unit tests (`ReviewTemplateService`):**
- `availableTemplates()` returns templates sorted alphabetically
- `loadSteps(from:)` parses `## - [ ]` lines correctly, skips non-heading lines
- `loadSteps(from:)` includes already-completed `## - [x]` lines (returns them with their description — appending re-adds them as unchecked)

**Manual smoke test:**
1. Open a plan in the Plans tab
2. Tap "Append Review" — popover shows templates from `docs/reviews/`
3. Select `architecture-compliance.md` — steps are appended to the plan markdown on disk
4. Inspect the markdown file — new `## - [ ]` lines appear at the end
5. Run the plan — review phases execute after the original phases, Claude reads the plan for context and reviews+fixes
