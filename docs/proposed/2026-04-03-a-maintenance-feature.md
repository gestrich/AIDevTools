## Relevant Skills

| Skill | Description |
|-------|-------------|
| `configuration-architecture` | Guide for wiring new config (task specs, tracking JSON) through the app layers |
| `logging` | Add logging to new discovery and execution paths |
| `swift-app-architecture:swift-architecture` | 4-layer architecture — new feature spans SDK, Service, Feature, and Apps layers |

## Background

The Maintenance Feature is a new AI-driven system for continuously maintaining a codebase. Unlike Claude Chain (which has a finite, user-authored list of tasks that are marked done), maintenance tasks are **ongoing**: a task runs against one or more target files, records the file state (git commit hash) when it last ran, and is re-run only when those files change or the task definition itself is versioned up.

Key design principles Bill specified:

- **Skip if unchanged**: A task is considered complete (skippable) when the recorded commit hash for each of its target files matches the current HEAD hash for those files, AND the task definition version hasn't changed.
- **Discovery is separate from execution**: A daily discovery job scans the repo for new/changed/removed target files and updates the tracking state. It never runs tasks — it only updates what needs running. Execution jobs read that state and run tasks.
- **Async-safe tracking**: Tracking state is stored in a JSON file (not markdown — relational model fits better). Double blank lines between entries are not needed for JSON; instead, atomic writes per entry key prevent conflicts.
- **Multi-file task groups**: A task's unique key is derived from its sorted set of target file paths. If any file in the group changes, the whole task is marked stale and must re-run.
- **PR output**: Each task execution results in a GitHub PR containing the AI's changes and an evaluation report (what it found, what it did, why).
- **Reuse PipelineService**: Task execution pipelines are built using the existing `PipelineService` and `PipelineSDK`. No new pipeline primitives needed.

### Tracking JSON Schema

```json
{
  "tasks": [
    {
      "key": "Sources/Foo.swift",
      "filePaths": ["Sources/Foo.swift"],
      "taskVersion": "1.0",
      "fileHashes": {
        "Sources/Foo.swift": "<git-commit-sha>"
      },
      "lastRunAt": "2026-04-03T12:00:00Z",
      "status": "complete"
    },
    {
      "key": "Sources/Bar.swift|Sources/Baz.swift",
      "filePaths": ["Sources/Bar.swift", "Sources/Baz.swift"],
      "taskVersion": "1.0",
      "fileHashes": {
        "Sources/Bar.swift": "<git-commit-sha>",
        "Sources/Baz.swift": "<git-commit-sha>"
      },
      "lastRunAt": null,
      "status": "pending"
    }
  ]
}
```

`status` is one of: `pending`, `complete`. Discovery sets `pending` when a hash or task version changes; execution sets `complete` after a successful PR.

### Maintenance Spec File

Each maintenance task is defined by a spec file (checked into the repo, alongside the tracking JSON or in a known directory):

```yaml
name: "Clean up service layer"
version: "1.0"
description: |
  Review each file for adherence to the service layer conventions. Remove dead code,
  fix naming, and ensure protocol conformance is correct.
discovery:
  mode: glob           # or: script, ai
  pattern: "Sources/Services/**/*.swift"
execution:
  maxOpenPRs: 1
  runTests: true
  prReport: true
```

`discovery.mode`:
- `glob` — standard file glob
- `script` — shell script that prints file paths
- `ai` — AI context scan to identify relevant files (free-form)

---

## - [ ] Phase 1: Define SDK models

**Skills to read**: `swift-app-architecture:swift-architecture`

Create a new `MaintenanceSDK` target in `Package.swift` (alphabetically placed). Define the core value types:

- `MaintenanceSpec` — parsed from YAML spec file. Fields: `name`, `version`, `description`, `discovery` (mode + pattern/script), `execution` (maxOpenPRs, runTests, prReport).
- `MaintenanceTaskEntry` — one entry in the tracking JSON. Fields: `key: String`, `filePaths: [String]`, `taskVersion: String`, `fileHashes: [String: String]`, `lastRunAt: Date?`, `status: MaintenanceTaskStatus`.
- `MaintenanceTaskStatus: String, Codable` — `pending`, `complete`.
- `MaintenanceTrackingState` — top-level tracking JSON wrapper. Field: `tasks: [MaintenanceTaskEntry]`.
- `MaintenanceTaskKey` — static helper that derives the canonical key from a sorted array of file paths (`paths.sorted().joined(separator: "|")`).

All types: `Codable`, `Sendable`, `public`.

Files:
- `Sources/SDKs/MaintenanceSDK/MaintenanceSpec.swift`
- `Sources/SDKs/MaintenanceSDK/MaintenanceTaskEntry.swift`
- `Sources/SDKs/MaintenanceSDK/MaintenanceTaskStatus.swift`
- `Sources/SDKs/MaintenanceSDK/MaintenanceTrackingState.swift`
- `Sources/SDKs/MaintenanceSDK/MaintenanceTaskKey.swift`

---

## - [ ] Phase 2: Discovery Service

**Skills to read**: `swift-app-architecture:swift-architecture`, `logging`

Create a `MaintenanceService` target. The discovery service scans a repo for target files, diffs them against the current tracking state, and writes an updated tracking JSON. It does **not** execute tasks.

`MaintenanceDiscoveryService` (protocol + implementation):

```swift
func discover(spec: MaintenanceSpec, repoPath: String, trackingURL: URL) async throws -> MaintenanceTrackingState
```

Steps:
1. Load existing `MaintenanceTrackingState` from `trackingURL` (or start empty).
2. Resolve target file paths using the spec's discovery mode:
   - `glob`: use `FileManager` glob expansion
   - `script`: run shell script, collect stdout lines as paths
   - `ai`: invoke Claude CLI with a prompt asking it to list relevant files
3. Group paths into task groups (for `glob`/`script`, each file is its own group; for `ai`, the AI returns groups).
4. For each group, compute the canonical `key`.
5. For each key:
   - **New**: add entry with `status: .pending`, `fileHashes: [:]`, `lastRunAt: nil`.
   - **Obsolete** (key no longer in discovered set): remove entry.
   - **Changed**: fetch current git commit SHA for each file path. If any SHA differs from stored hash, OR `taskVersion` differs from spec version → set `status: .pending`.
   - **Unchanged**: leave as-is.
6. Write updated state back to `trackingURL` atomically.

Add `Logger(label: "MaintenanceDiscoveryService")` with debug/info logging at each step.

Files:
- `Sources/Services/MaintenanceService/MaintenanceDiscoveryService.swift`
- `Sources/Services/MaintenanceService/MaintenanceDiscoveryServiceProtocol.swift`

---

## - [ ] Phase 3: Execution Service

**Skills to read**: `swift-app-architecture:swift-architecture`, `logging`

Create `MaintenanceExecutionService` that picks the next `pending` task from the tracking state, runs it via `PipelineService`, and updates the tracking state on completion.

```swift
func executeNext(spec: MaintenanceSpec, repoPath: String, trackingURL: URL) async throws -> MaintenanceExecutionResult
```

Steps:
1. Load tracking state. Find the first entry with `status: .pending`. If none, return `.noWork`.
2. Build a `PipelineService` pipeline:
   - AI step: run Claude CLI with the spec's `description` prompt, targeting the task's `filePaths`.
   - If `execution.runTests`: add a test-run step after the AI step.
   - `PRStep` with `maxOpenPRs` from spec and a PR body that includes the AI's evaluation report.
3. Execute the pipeline.
4. On success: update entry — set `status: .complete`, `fileHashes` to current SHAs, `lastRunAt` to now, `taskVersion` to spec version. Write state.
5. On failure: leave `status: .pending` (will retry next run). Log error.

`MaintenanceExecutionResult`:
```swift
enum MaintenanceExecutionResult {
    case noWork
    case completed(key: String, prURL: String)
    case failed(key: String, error: Error)
}
```

Files:
- `Sources/Services/MaintenanceService/MaintenanceExecutionService.swift`
- `Sources/Services/MaintenanceService/MaintenanceExecutionServiceProtocol.swift`
- `Sources/Services/MaintenanceService/MaintenanceExecutionResult.swift`

---

## - [ ] Phase 4: MaintenanceFeature use cases

**Skills to read**: `swift-app-architecture:swift-architecture`

Create a `MaintenanceFeature` target with two use cases (matching the two jobs that run on separate schedules):

**`RunMaintenanceDiscoveryUseCase`**
- Loads spec from a given spec file URL
- Calls `MaintenanceDiscoveryService.discover(...)`
- Returns updated `MaintenanceTrackingState`

**`RunMaintenanceTaskUseCase`**
- Loads spec from spec file URL
- Calls `MaintenanceExecutionService.executeNext(...)`
- Returns `MaintenanceExecutionResult`

Both use cases are injected with their respective services. No business logic beyond orchestration.

Files:
- `Sources/Features/MaintenanceFeature/RunMaintenanceDiscoveryUseCase.swift`
- `Sources/Features/MaintenanceFeature/RunMaintenanceTaskUseCase.swift`

---

## - [ ] Phase 5: CLI commands

**Skills to read**: `swift-app-architecture:swift-architecture`

Add two subcommands to the `ai-dev-tools-kit` CLI (alphabetically in the command list):

**`maintenance discover`**
```
swift run ai-dev-tools-kit maintenance discover --spec <path-to-spec.yaml> --repo <repo-path>
```
Runs `RunMaintenanceDiscoveryUseCase`. Prints a summary: N added, N removed, N marked stale.

**`maintenance run`**
```
swift run ai-dev-tools-kit maintenance run --spec <path-to-spec.yaml> --repo <repo-path>
```
Runs `RunMaintenanceTaskUseCase` once (next pending task). Prints result: task key, PR URL, or "no work".

The tracking JSON path is derived from the spec file path (same directory, `<spec-name>.tracking.json`).

Files:
- `Sources/Apps/AIDevToolsKitCLI/MaintenanceCommand.swift`

---

## - [ ] Phase 6: Validation

**Skills to read**: `logging`

**Unit tests** — add `MaintenanceSDKTests` and `MaintenanceServiceTests` targets:
- `MaintenanceTaskKeyTests`: verify key derivation sorts paths and joins with `|`.
- `MaintenanceDiscoveryServiceTests`: mock git SHA lookup; verify add/remove/stale/skip logic.
- `MaintenanceTrackingStateTests`: round-trip `Codable` encoding.

**CLI smoke test** — use a local test repo:
```bash
# Create a minimal spec
cat > /tmp/test-maintenance.yaml <<EOF
name: "Test"
version: "1.0"
description: "Review this file."
discovery:
  mode: glob
  pattern: "Sources/**/*.swift"
execution:
  maxOpenPRs: 1
  runTests: false
  prReport: true
EOF

swift run ai-dev-tools-kit maintenance discover --spec /tmp/test-maintenance.yaml --repo <some-test-repo>
# Verify tracking JSON created with pending entries

swift run ai-dev-tools-kit maintenance run --spec /tmp/test-maintenance.yaml --repo <some-test-repo>
# Verify PR created, tracking JSON updated to complete

swift run ai-dev-tools-kit maintenance run --spec /tmp/test-maintenance.yaml --repo <some-test-repo>
# Verify "no work" (already complete, files unchanged)
```

**Log verification**:
```bash
cat ~/Library/Logs/AIDevTools/aidevtools.log | jq 'select(.label | startswith("Maintenance"))'
```
Confirm discovery and execution steps are logged at appropriate levels.
