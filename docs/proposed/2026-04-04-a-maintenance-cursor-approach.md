## Open Questions

1. **Range definition**: Is the range (`A/xyz -> A/zzz`) a lexicographic path range, or does it use a glob pattern? For example, does `Sources/Services/A -> Sources/Services/Z` mean all paths that sort lexicographically between those two strings?

2. **Wrap-around behavior**: When the cursor reaches the end of the range, does it wrap back to the beginning? This would mean maintenance is a continuous cycle rather than a one-time pass.

3. **"Refactored" definition**: A file counts as refactored when the AI produces at least one change (diff is non-empty). Confirmed? Or is there a more specific definition — e.g., only when a PR is opened?

4. **Skipping missing files**: If a file in the range no longer exists on disk (deleted or renamed), do we skip it and advance the cursor, or halt with an error?

5. **Cursor granularity**: The cursor stores the *last processed* path. On the next run, we start at the path *after* the cursor in sorted order. Is "after" strictly lexicographic, or do we re-expand the file list from disk each run (which handles adds/deletes naturally)?

6. **One job at a time — enforcement**: Is this a soft convention (documented) or hard-enforced via a lock file or state check?

7. **PR-per-file vs. PR-per-run**: With the hash approach, each file gets its own PR. With the cursor approach and `maxRefactoredFiles > 1`, do we open one PR with all changed files, or one PR per changed file?

8. **Range ends inclusive?**: Is the range `A/xyz -> A/zzz` inclusive on both ends?

---

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture — relevant for placing new models and services |
| `logging` | Add logging to execution paths |

---

## Background

This document compares two architectural approaches for the Maintenance feature. The existing plan ([2026-04-03-a-maintenance-feature.md](2026-04-03-a-maintenance-feature.md)) uses **per-file hash tracking with discovery**. This document proposes an alternative: **cursor-based range scanning with no discovery**.

---

## Cursor Approach

### Core Concept

Instead of maintaining a per-file hash map and a discovery phase, the system maintains a single **cursor**: the path of the last file processed. A **range** in `config.yaml` defines the set of paths subject to maintenance (`startPath -> endPath`, lexicographic). On each run:

1. Load cursor from `state.json`
2. Expand the sorted file list from disk for the range
3. Find the file after the cursor in that list (or start from the beginning if cursor is unset or past the end)
4. Process files forward from that position, subject to `maxAnalysisFiles` and `maxRefactoredFiles`
5. Store the last-analyzed path as the new cursor

### `config.yaml` Schema

```yaml
maxOpenPRs: 1
maxAnalysisFiles: 10      # max files to look at in one run (default: 1)
maxRefactoredFiles: 3     # max files to actually change (default: 1, never > maxAnalysisFiles)
range:
  start: "Sources/Services/Auth"
  end: "Sources/Services/Zzz"
```

- `maxAnalysisFiles`: how many files the AI will be invoked on in one run
- `maxRefactoredFiles`: how many of those may produce a non-empty diff; once this limit is hit, the run stops even if `maxAnalysisFiles` is not exhausted
- `maxRefactoredFiles` defaults to 1; `maxAnalysisFiles` defaults to 1; `maxRefactoredFiles` must always be ≤ `maxAnalysisFiles`

### `state.json` Schema

```json
{
  "cursor": "Sources/Services/FooService.swift"
}
```

Single field. Written atomically after each run.

### File Layout

```
claude-chain-maintenance/<task-name>/
  config.yaml    # maxOpenPRs, maxAnalysisFiles, maxRefactoredFiles, range
  spec.md        # AI instructions only
  state.json     # cursor only
```

### Execution Algorithm

```
sortedPaths = expandRangeFromDisk(config.range)
startIndex  = indexAfterCursor(sortedPaths, state.cursor) or 0

analyzed = 0
refactored = 0

for path in sortedPaths[startIndex...]:
    if analyzed >= maxAnalysisFiles: break
    if refactored >= maxRefactoredFiles: break
    if !exists(path): skip, advance cursor, continue

    run AI on path
    analyzed += 1

    if diff is non-empty:
        refactored += 1

    cursor = path   # always advance, even if no change

save cursor to state.json
```

---

## Comparison: Hash Tracking vs. Cursor

| Dimension | Hash Tracking (existing plan) | Cursor (this plan) |
|---|---|---|
| **State per file** | `lastRunHash`, `lastRunAt` per path | Single cursor path |
| **Discovery phase** | Required — expands glob, diffs state.json | None — range expanded from disk at runtime |
| **Re-run trigger** | File changes (hash mismatch) | Cursor reaches file again (wrap-around) |
| **Parallelism** | Multiple jobs possible (different files) | One job at a time (shared cursor) |
| **Handles file adds** | Discovery adds new entries with null hash | File appears in sorted list; cursor passes it naturally |
| **Handles file deletes** | Discovery removes obsolete entries | Skip missing files at runtime |
| **State file size** | Grows with number of files | Fixed size (one path) |
| **"What changed since last run?"** | Precise — hash diff tells you exactly | Unknown — cursor just tracks position, not history |
| **Starvation risk** | No — any changed file is eligible | Yes — files near the cursor start get processed more frequently if runs are frequent |
| **Ordering guarantee** | None — picks first stale entry | Strong — alphabetical sweep |
| **Config complexity** | `maxOpenPRs`, `discoveryGlob` | `maxOpenPRs`, `maxAnalysisFiles`, `maxRefactoredFiles`, `range.start/end` |
| **Multi-file per run** | One file per run (by design) | Up to `maxAnalysisFiles` per run |
| **PR strategy** | One PR per file | TBD — one PR for all changes in run, or one per changed file |
| **Implementation complexity** | Higher (discovery service, hash computation, state migration) | Lower (cursor read/write, range expansion) |

### When hash tracking wins

- You care about **re-running only when a file actually changed** — hash tracking is precise; cursor will re-run files that haven't changed when it wraps around.
- You want **parallel jobs** across different files — cursor requires serialization.
- You need **audit history** (`lastRunAt` per file) for reporting or debugging.

### When cursor wins

- You want **simplicity** — no discovery, no hash computation, minimal state.
- You want a **continuous sweep** — maintenance is a rolling process over the whole codebase, not reactive to changes.
- Your codebase grows/shrinks frequently — range expansion from disk handles this without a separate discovery step.
- You want **batch processing** — `maxAnalysisFiles` and `maxRefactoredFiles` together let you tune throughput per run.

### Key tension

Hash tracking answers: *"which files need attention right now?"*  
Cursor answers: *"which file is next in the rotation?"*

These are meaningfully different maintenance philosophies. Hash tracking is **reactive** (re-run when content changes). Cursor is **iterative** (sweep through everything on a schedule, changes or not).

---

## Implementation Phases (if cursor approach is chosen)

### - [ ] Phase 0: Refactor RunChainTaskUseCase (same as existing plan)

No change from the existing plan's Phase 0. This is a prerequisite regardless of approach.

---

### - [ ] Phase 1: CursorMaintenanceSDK models

**Skills to read**: `swift-app-architecture:swift-architecture`

Create `MaintenanceSDK` target with cursor-based models.

**`MaintenanceCursorState`**:
```swift
public struct MaintenanceCursorState: Codable, Sendable {
    public var cursor: String?   // last-processed path; nil = start from beginning
}
```

**`MaintenanceCursorConfig`**:
```swift
public struct MaintenanceCursorConfig: Sendable {
    public let maxOpenPRs: Int           // default: 1
    public let maxAnalysisFiles: Int     // default: 1
    public let maxRefactoredFiles: Int   // default: 1, never > maxAnalysisFiles
    public let rangeStart: String
    public let rangeEnd: String
}
```

**`MaintenanceCursorTaskSource`** — implements `TaskSource`:
- `nextTask()`: expand sorted file list from `rangeStart...rangeEnd`; find index after cursor; return `PendingTask` for next path; read spec.md; return `PendingTask(id: path, instructions: specContent + "\n\nFile: \(path)", skills: [])`
- `markComplete(_ task:)`: write cursor = `task.id` to state.json

Files:
- `Sources/SDKs/MaintenanceSDK/MaintenanceCursorConfig.swift`
- `Sources/SDKs/MaintenanceSDK/MaintenanceCursorState.swift`
- `Sources/SDKs/MaintenanceSDK/MaintenanceCursorTaskSource.swift`
- `Sources/Services/ClaudeChainService/MaintenanceChainTaskSource.swift` (same display-side protocol as hash approach)

---

### - [ ] Phase 2: Cursor Execution Service

**Skills to read**: `swift-app-architecture:swift-architecture`, `logging`

`MaintenanceCursorExecutionService`:

```swift
func executeRun(config: MaintenanceCursorConfig, repoPath: String, taskDirectoryURL: URL) async throws -> MaintenanceCursorRunResult
```

Implements the loop: advance cursor, invoke AI, track `analyzed` and `refactored`, write cursor after each file, stop when either limit is reached.

```swift
struct MaintenanceCursorRunResult: Sendable {
    let analyzed: Int
    let refactored: Int
    let finalCursor: String?
    let skipped: [String]    // paths that no longer exist on disk
}
```

Files:
- `Sources/Services/MaintenanceService/MaintenanceCursorExecutionService.swift`
- `Sources/Services/MaintenanceService/MaintenanceCursorRunResult.swift`

---

### - [ ] Phase 3: CLI command

Same shape as existing plan's Phase 5. `maintenance run` with `--task` and `--repo` flags. Prints: N analyzed, N refactored, cursor advanced to `<path>`.

---

### - [ ] Phase 4: Validation

**Unit tests**:
- `MaintenanceCursorStateTests`: round-trip Codable; nil cursor starts from beginning; cursor past end wraps.
- `MaintenanceCursorTaskSourceTests`: `maxAnalysisFiles` limit respected; `maxRefactoredFiles` limit stops run early; missing files skipped.

**CLI smoke test**:
```bash
mkdir -p /tmp/test-claude-chain-maintenance
echo "maxOpenPRs: 1\nmaxAnalysisFiles: 3\nmaxRefactoredFiles: 1\nrange:\n  start: Sources/Services/A\n  end: Sources/Services/Z" > /tmp/test-claude-chain-maintenance/config.yaml
echo "Review this file for service layer compliance." > /tmp/test-claude-chain-maintenance/spec.md

swift run ai-dev-tools-kit maintenance run --task /tmp/test-claude-chain-maintenance --repo <repo>
# Verify state.json cursor set to first processed path
# Verify up to 1 PR opened (maxRefactoredFiles=1)

swift run ai-dev-tools-kit maintenance run --task /tmp/test-claude-chain-maintenance --repo <repo>
# Verify cursor advanced past previous position
```
