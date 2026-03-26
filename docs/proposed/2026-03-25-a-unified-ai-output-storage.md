## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer Swift app architecture (Apps, Features, Services, SDKs) |
| `ai-dev-tools-debug` | File paths, CLI commands, and artifact structure for AIDevTools |

## Background

The AI Evaluations feature and the Architecture Planner feature both run Claude and capture output, but they use completely different storage and display mechanisms:

- **Evals**: Writes raw stdout/stderr to `artifacts/raw/<provider>/<caseId>.stdout`, structured JSON to `artifacts/<provider>/<caseId>.json`, and summaries to `artifacts/<provider>/summary.json`. Uses `OutputService` for read/write and `ArtifactWriter` for artifact files. The Mac app loads and displays these via `EvalRunnerModel.loadLastResults()` and `ReadCaseOutputUseCase`. UI uses `OutputPanel` (private to `EvalResultsView.swift`).

- **Architecture Planner**: Stores structured results (requirements, components, decisions) in SwiftData via `ArchitecturePlannerStore`. Raw AI output is only held in memory (`currentOutput: String` on `ArchitecturePlannerModel`) and is never persisted — it's lost when the view changes or the app restarts. The UI has its own inline `outputPanel` in `ArchitecturePlannerDetailView`.

The goals are:
1. **Shared UI**: A single reusable output display component used by both features (and future AI-running features).
2. **Shared storage/retrieval**: A common mechanism for persisting and loading raw AI output so the architecture planner's output survives across sessions, and both features use the same code path.

## Phases

## - [x] Phase 1: Extract shared `OutputPanel` view

**Skills to read**: `swift-architecture`

Currently `OutputPanel` and `DetailSection` are `private` structs inside `EvalResultsView.swift` (lines 691-745). The architecture planner has its own nearly identical inline output panel in `ArchitecturePlannerDetailView.swift` (lines 213-239).

Tasks:
- Move `OutputPanel` to a new file in the Mac app's shared Views directory (e.g. `AIDevToolsKitMac/Views/Components/OutputPanel.swift`)
- Make it `internal` (or `public` if needed across modules) instead of `private`
- Ensure it keeps both features' capabilities: optional title, auto-scroll toggle, monospaced font, text selection
- Update `EvalResultsView` to use the extracted `OutputPanel`
- Update `ArchitecturePlannerDetailView` to use the extracted `OutputPanel` instead of its inline version
- Verify both UIs render identically after the extraction

## - [ ] Phase 2: Create `AIOutputStore` concrete struct

**Skills to read**: `swift-architecture`

A simple concrete struct that stores and retrieves raw AI text output by string key. No protocol, no identifier types — just a key-value store backed by the file system.

Tasks:
- Create `AIOutputStore` struct (Sendable) in a shared SDK or Services module
- Constructor takes a `baseDirectory: URL` — the root directory for all stored outputs
- API:
  - `write(output: String, key: String) throws` — writes text to `<baseDirectory>/<key>.stdout`, creating intermediate directories as needed
  - `read(key: String) -> String?` — returns file contents or `nil` if not found
  - `delete(key: String) throws` — removes the file if it exists
- Keys use `/` to encode hierarchy (e.g. `"claude/my-suite.my-case"`, `"job-abc/form-requirements"`) — the store splits on `/` to create subdirectories
- Uses `atomically: true` for writes
- Add unit tests for write/read/delete round-trip and `nil` on missing key

## - [ ] Phase 3: Migrate eval `OutputService` raw output to use `AIOutputStore`

**Skills to read**: `swift-architecture`, `ai-dev-tools-debug`

Adapt the eval system's raw stdout/stderr writing and reading to go through `AIOutputStore`, preserving the existing directory layout.

Tasks:
- Construct `AIOutputStore` with base directory = `<outputDir>/artifacts/raw/`
- Update `OutputService.write()` to delegate raw stdout/stderr writing to `AIOutputStore`
  - Key for stdout: `"<provider>/<caseId>"` (produces `artifacts/raw/<provider>/<caseId>.stdout`)
  - Stderr stays as a parallel write with `.stderr` extension (or use a separate key convention like `"<provider>/<caseId>.stderr"`)
  - The structured JSON and summary writing stay in `OutputService`/`ArtifactWriter` (eval-specific grading artifacts)
- Update `OutputService.readFormattedOutput()` to load raw stdout via `AIOutputStore.read()` then apply formatting
- Run existing eval CLI commands to verify no regression

## - [ ] Phase 4: Add raw output persistence to Architecture Planner

**Skills to read**: `swift-architecture`

The architecture planner currently discards raw AI output after each step. Wire it to persist and reload output via `AIOutputStore`.

Tasks:
- Construct `AIOutputStore` with base directory = `<dataPath>/architecture-planner/<repoName>/output/`
- In `ArchitecturePlannerModel.runNextStep()`, after each step completes, write `currentOutput` to the store
  - Key: `"<jobId>/<step-index>"` (e.g. `"abc123/1"`)
- Add a method to load persisted output for a given job/step
- Update `ArchitecturePlannerDetailView` to show a "View Output" disclosure for completed steps that loads from the store
- Live streaming `currentOutput` stays the same for in-progress steps — persistence happens on completion
- Also persist on failure (partial output is valuable for debugging)

## - [ ] Phase 5: Validation

**Skills to read**: `swift-testing`

Tasks:
- Unit tests for `AIOutputStore`: write/read/delete, missing key returns nil, nested key directory creation
- Unit tests verifying `OutputService` read/write still works after the refactor
- Manual verification:
  - Run an eval via CLI (`swift run ai-dev-tools-kit run-evals ...`) and confirm artifacts are written correctly
  - Open the Mac app, run an architecture planner step, close the view, reopen — verify the output is still visible
  - Verify both `OutputPanel` instances render correctly in both features
- Build the Mac app and CLI to confirm no compile errors
