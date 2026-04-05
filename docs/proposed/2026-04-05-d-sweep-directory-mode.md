## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | 4-layer architecture guidelines (Apps, Features, Services, SDK) |
| `ai-dev-tools-swift-testing` | Swift Testing conventions for unit tests |
| `ai-dev-tools-code-quality` | Code quality checks (force unwraps, raw strings, etc.) |
| `ai-dev-tools-enforce` | Post-change enforcement verification |

## Background

ClaudeChain currently supports two sweep strategies: spec-based (one-shot task list from markdown) and file-based sweep (walks files one-by-one with a cursor). The file sweep is configured via `filePattern` (glob), an optional `SweepScope` (from/to path range), and `scanLimit`/`changeLimit`. The cursor tracks the last processed file path in `state.json`.

Bill wants to extend the sweep to support directory-based iteration using the **existing `filePattern` field** — no new config fields needed. The mode is inferred from the pattern itself via standard glob conventions:

| Pattern | Mode | Each task is... |
|---------|------|-----------------|
| `Sources/**/*.swift` | File sweep | One matched file |
| `Sources/*/` | Directory sweep (one level) | One immediate subdir of `Sources` |
| `Sources/**/*/` | Directory sweep (all depths) | One directory at any nesting depth |
| `Sources/MyModule/` | Directory sweep (specific) | That one directory |

**Rule**: trailing `/` → directory mode. No trailing `/` → file mode (existing behavior, unchanged).

This covers all three use cases:
1. Walk file types to any nesting: `Sources/**/*.swift`
2. Walk top-level folders in a folder: `Sources/*/`
3. Treat a specific folder as a single unit: `Sources/MyModule/`

In directory mode, skip detection changes: instead of comparing a file's blob hash, check whether any file inside the directory changed since the last cursor commit (`git diff --quiet <cursorCommit> HEAD -- <dir>`). Everything else (cursor mechanics, `SweepScope`, limits) works identically.

The deferred "multi-folder group" case (disparate folders from different parts of the tree triggering as one unit) is out of scope.

## Phases

## - [x] Phase 1: Mode Detection in `SweepConfig`

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Added `isDirectoryMode` as a computed property (not stored) to keep `SweepConfig` a simple value type with no new init parameters or config fields. The property is `public` to match the rest of the struct's API surface.

**Skills to read**: `ai-dev-tools-architecture`

Add a computed property to `SweepConfig` that infers the sweep mode from `filePattern`. No new stored fields.

- **File**: `AIDevToolsKit/Sources/Services/SweepService/SweepConfig.swift`
  - Add `var isDirectoryMode: Bool { filePattern.hasSuffix("/") }`
  - No changes to config.yaml parsing — `filePattern` already accepts any string

## - [x] Phase 2: Directory Enumeration

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Added `expandDirectories(pattern:repoPath:)` that walks the repo enumerating directories, strips the trailing `/` before glob-to-regex conversion, and returns results sorted alphabetically. Branched `candidatePaths` on `config.isDirectoryMode` so both `loadProject` and `nextTask` use the correct expansion path without duplicating the branch.

**Skills to read**: `ai-dev-tools-architecture`

In `SweepClaudeChainSource`, add a method to expand a directory-mode `filePattern` into a sorted list of directory paths. The existing `globToRegex()` utility should be reusable.

- **File**: `AIDevToolsKit/Sources/Services/ClaudeChainService/SweepClaudeChainSource.swift`
  - Add `func expandDirectories(pattern: String, repoPath: String) throws -> [String]`
    - Walk the repo path, collecting directory paths (not files)
    - Filter against the glob pattern via `globToRegex()` (strip trailing `/` before regex conversion if needed)
    - Sort alphabetically
    - Apply `SweepScope` if present (works unchanged — scope is string comparison on paths)
  - In `loadProject()`, branch on `config.isDirectoryMode`:
    - `true` → call `expandDirectories`
    - `false` → existing file expansion (unchanged)

## - [x] Phase 3: Skip Detection for Directories

**Skills used**: none
**Principles applied**: Added `canSkipDirectory` that reuses `logGrep` to find the cursor commit (same as `canSkip`) then delegates to a new `GitClient.hasDirectoryChanges` method which runs `git diff --name-only <cursorCommit> HEAD <path>` — empty output means skip. Branched `nextTask()` on `config.isDirectoryMode` to call the correct skip check.

**Skills to read**: (none beyond existing code)

Adapt skip detection to work on a directory path.

Currently `canSkip(path:)` compares a file's blob hash at the cursor commit vs HEAD. For directories the equivalent is checking if any file inside changed.

- **File**: `AIDevToolsKit/Sources/Services/ClaudeChainService/SweepClaudeChainSource.swift`
  - Add `func canSkipDirectory(path: String) async throws -> Bool`
    - If no cursor commit exists yet → return `false` (always process on first pass)
    - Otherwise: run `git diff --quiet <cursorCommit> HEAD -- <path>` (exit code 0 = no changes = skip)
  - In `nextTask()`, call `canSkipDirectory` instead of `canSkip` when `config.isDirectoryMode`

## - [x] Phase 4: Task Construction for Directory Mode

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Derived `scopeLabel` inline in `nextTask()` from `config.isDirectoryMode` — no new methods or stored properties needed. The `id` was already the directory path; only the instruction label changed from `"File"` to `"Directory"` to give the AI correct context about what it's operating on.

When building an `AITask` for a directory, pass the directory path as the scope context instead of a single file path.

- **File**: `AIDevToolsKit/Sources/Services/ClaudeChainService/SweepClaudeChainSource.swift`
  - In `nextTask()`, when `config.isDirectoryMode`:
    - The "current item" (cursor value) is the directory path
    - Pass the directory path as the task's file/scope context
    - Task instructions from config.yaml are unchanged — the prompt already describes what to do

## - [x] Phase 5: Cursor Semantics

**Skills used**: none
**Principles applied**: No structural changes needed — `SweepState.cursor` is already `String?` and all cursor mechanics (`nextPathIndex`, `finalizeBatch`, `processedPaths`) operate on plain strings and work identically for directory paths. Updated the `cursor` doc comment and two log messages ("files" → "paths") to be mode-agnostic.

`SweepState.cursor` is already `String?` — no model changes needed. Directory paths slot in directly.

- **File**: `AIDevToolsKit/Sources/Services/ClaudeChainService/SweepClaudeChainSource.swift`
  - Cursor advancement: same index-based logic, operating on the sorted directory list
  - Cursor commit message: `[claude-sweep] task=<name> cursor=<dirPath>\nprocessed: <dir1> <dir2> ...`
  - `finalizeBatch()` unchanged structurally — just ensure directory paths flow through

## - [x] Phase 6: Tests

**Skills used**: `ai-dev-tools-swift-testing`
**Principles applied**: Created `SweepConfigTests.swift` with two focused tests for `isDirectoryMode`. Added `makeSubDir` and `gitCommitAll` helpers to the existing test file, then added two new suites covering directory enumeration (single-star vs double-star), scope filtering, task instructions label, cursor advancement, scanLimit, and canSkipDirectory (no commit → process, unchanged → skip, changed → process).

**Skills to read**: `ai-dev-tools-swift-testing`

- **File**: `AIDevToolsKit/Tests/Services/SweepServiceTests/SweepConfigTests.swift` (new if needed)
  - `isDirectoryMode` returns `true` for patterns ending in `/`, `false` otherwise
- **File**: `AIDevToolsKit/Tests/Services/ClaudeChainServiceTests/SweepClaudeChainSourceTests.swift`
  - Directory enumeration: `Sources/*/` expands to correct immediate subdirs only
  - Directory enumeration: `Sources/**/*/` expands recursively
  - `SweepScope` applies correctly to directory paths
  - `canSkipDirectory`: `false` with no cursor commit; `true` when dir unchanged; `false` when dir has changes
  - Cursor advances through directory list and wraps correctly
  - `scanLimit` and `changeLimit` behave the same as in file mode

## - [x] Phase 7: Validation

**Skills used**: `ai-dev-tools-swift-testing`
**Principles applied**: Ran all 21 sweep tests (SweepConfigTests + SweepClaudeChainSourceTests) — all passed with zero regressions across 6 suites covering file mode, directory mode, skip detection, cursor advancement, scanLimit, and SweepScope.

- Run all existing sweep tests — no regressions
- Run new Phase 6 tests
- Optional: dry-run (`--dry-run`) against a local repo with `filePattern: "Sources/*/"` to confirm directory enumeration and cursor output

## - [ ] Phase 8: Enforce

**Skills to read**: `ai-dev-tools-enforce`

- Run `ai-dev-tools-enforce` on all files changed during this plan
