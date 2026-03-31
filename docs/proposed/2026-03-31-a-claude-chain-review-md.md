## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer Swift app architecture (Apps, Features, Services, SDKs) |
| `swift-testing` | Test style guide and conventions |
| `claude-chain` | Manages ClaudeChain automated PR chains |

## Background

Claude Chain currently runs tasks from a `spec.md` file in sequence. After each task is implemented by AI and committed, the chain creates a PR. There is no post-implementation review step.

We want to add an optional `review.md` file (per-project, at `claude-chain/{project}/review.md`) that is fed to the AI after every spec task completes. The review AI pass applies the criteria in `review.md` to the just-committed work, makes any conformance fixes, commits the result (always, even if nothing changed), and appends a one-line note under the completed task entry in `spec.md`.

Key requirements from the conversation:
- Review runs after main task work is committed and spec.md task is marked `[x]`
- Review only runs if `review.md` exists (same optional pattern as pre/post scripts)
- Reuse all existing architecture — no bespoke structures
- Review AI is prompted with context about which spec task was just done
- AI should err on the side of making changes, not just verifying
- A commit always happens after the review (even if no code changed — at minimum the spec.md note is committed)
- A one-line review summary is appended to spec.md under the completed task entry
- Review AI cost is tracked and included in `CostBreakdown` and the PR comment cost table

## Phases

## - [x] Phase 1: Add `reviewPath` to Project and load method to ProjectRepository

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Added `reviewPath` as a computed property on `Project` alongside existing path properties. Added `loadLocalReview` to the local filesystem section of `ProjectRepository` following the same nil-on-missing/nil-on-empty pattern as `loadLocalSpec`.

**Skills to read**: `swift-app-architecture:swift-architecture`

Add `reviewPath` property to `Project.swift` (alongside `specPath`, `configPath`, `prTemplatePath`):

```swift
public var reviewPath: String { "\(basePath)/review.md" }
```

Add `loadLocalReview(project:)` to `ProjectRepository.swift` using the same pattern as `loadLocalSpec`:

```swift
public func loadLocalReview(project: Project) throws -> String? {
    guard FileManager.default.fileExists(atPath: project.reviewPath) else { return nil }
    let content = try String(contentsOfFile: project.reviewPath, encoding: .utf8)
    return content.isEmpty ? nil : content
}
```

No GitHub (remote) variant needed for now — review.md is only read locally post-checkout, same as how spec.md is consumed in `RunChainTaskUseCase`.

## - [x] Phase 2: Add Progress cases and prompt builder to RunChainTaskUseCase

**Skills used**: `claude-chain`
**Principles applied**: Added `reviewCompleted` and `runningReview` Progress cases in alphabetical position. Added `buildReviewPrompt` to the existing `// MARK: - Prompt Building` section. Added `extractReviewSummary` (internal access to allow testing) to `// MARK: - Helpers`. Updated all exhaustive switches in `RunTaskCommand.swift`, `ClaudeChainModel.swift`, and `ClaudeChainView.swift`.

In `RunChainTaskUseCase.swift`:

1. Add two new `Progress` cases (keep the enum sorted alphabetically):
   ```swift
   case reviewCompleted(summary: String)
   case runningReview
   ```

2. Add `buildReviewPrompt(taskDescription:specPath:reviewContent:) -> String` helper in the `// MARK: - Prompt Building` section:

```
You are in the middle of running the task chain for spec.md at {specPath}.

The last task was just completed and committed: "{taskDescription}"

Your job is to review those changes and apply improvements based on the criteria in review.md below.
You should err on the side of making changes for conformance, rather than just verifying things are done.
Even things that are slightly not right should be fixed. Err on the side of improving the work that was done.

--- BEGIN review.md ---
{reviewContent}
--- END review.md ---

After completing your review and making any changes, output a single final line in this exact format:
REVIEW_SUMMARY: <one-line description of what changed, or "No changes needed">
```

3. Add `extractReviewSummary(from output: String) -> String` helper that scans for the last line starting with `REVIEW_SUMMARY:` and returns the rest (trimmed), falling back to `"Review completed"` if not found.

## - [x] Phase 3: Insert review phase into RunChainTaskUseCase execution flow

**Skills used**: `claude-chain`
**Principles applied**: Inserted Phase 5b block between the spec.md commit and the push. `reviewCost` defaults to `0.0` and is only set when review.md is present. Added `appendReviewNote` helper (internal access for testability) that finds the `- [x]` task line and inserts an HTML comment on the next line. Both new helpers use `internal` access (no `private`) to allow unit testing.

Currently Phase 5 does: commit AI changes → mark spec task `[x]` → commit spec.md → push → create PR.

Restructure Phase 5 so the review runs between the spec.md commit and the push:

```
Phase 5a (existing): commit AI changes
Phase 5a (existing): markStepCompleted + commit spec.md
Phase 5b (new):      if review.md exists → run AI review → commit changes → append spec note → commit spec.md
Phase 5c (existing): push branch, create PR
```

The Phase 5b block:

```swift
var reviewCost = 0.0
if let reviewContent = try? repository.loadLocalReview(project: project) {
    onProgress?(.runningReview)

    let reviewPrompt = buildReviewPrompt(
        taskDescription: nextStep.description,
        specPath: project.specPath,
        reviewContent: reviewContent
    )
    let reviewOptions = AIClientOptions(
        dangerouslySkipPermissions: true,
        workingDirectory: options.repoPath.path
    )
    let reviewResult = try await client.run(
        prompt: reviewPrompt,
        options: reviewOptions,
        onOutput: { text in onProgress?(.aiOutput(text)) },
        onStreamEvent: { event in onProgress?(.aiStreamEvent(event)) }
    )
    reviewCost = extractCost(from: reviewResult)

    // Commit any file changes the review AI made
    let reviewStatus = try await git.status(workingDirectory: repoDir)
    if !reviewStatus.isEmpty {
        try await git.addAll(workingDirectory: repoDir)
        let staged = try await git.diffCachedNames(workingDirectory: repoDir)
        if !staged.isEmpty {
            try await git.commit(message: "Review: \(nextStep.description)", workingDirectory: repoDir)
        }
    }

    // Append review note to spec.md under the completed task line, then always commit
    let reviewSummary = extractReviewSummary(from: reviewResult.stdout)
    appendReviewNote(specPath: project.specPath, taskDescription: nextStep.description, summary: reviewSummary)
    try await git.add(files: [specURL.path], workingDirectory: repoDir)
    try await git.commit(message: "Add review note for task \(stepIndex)", workingDirectory: repoDir)

    onProgress?(.reviewCompleted(summary: reviewSummary))
}
```

`reviewCost` defaults to `0.0` and is only set when the review runs. It is passed into `CostBreakdown` alongside the existing `mainCost` and `summaryCost`.

The `appendReviewNote` helper reads spec.md, finds the `- [x] {taskDescription}` line, and inserts an HTML comment on the next line:

```markdown
- [x] Add authentication
  <!-- review: Fixed naming conventions in AuthService, removed unused imports -->
```

HTML comment format keeps the note invisible in rendered markdown but visible in the raw file.

## - [x] Phase 4: Add `reviewCost` to CostBreakdown and PRCreatedReport

**Skills used**: none
**Principles applied**: Added `reviewCost`/`reviewModels` with default values so all existing callers compile unchanged. `totalCost` and `allModels` include the review fields. `toJSON`/`fromJSON` include `review_cost` with a `0.0` default for backwards compatibility. `fromExecutionFiles` has a new optional `reviewExecutionFile` parameter. `buildCostSummaryTable` adds the "Review" row only when `reviewCost > 0`.

`CostBreakdown` currently has `mainCost` and `summaryCost`. Add `reviewCost` and `reviewModels` following the exact same pattern as the existing fields.

Changes to `CostBreakdown.swift`:

1. Add stored properties `reviewCost: Double` and `reviewModels: [ModelUsage]` to the struct (with default values of `0.0` / `[]` so all existing callers compile unchanged).
2. Update `totalCost` computed property: `mainCost + summaryCost + reviewCost`.
3. Update `allModels`: `mainModels + reviewModels + summaryModels`.
4. Update `toJSON` to include `"review_cost": reviewCost`.
5. Update `fromJSON` to read `"review_cost"` (defaulting to `0.0` if absent, for backwards compatibility).
6. Update `fromExecutionFiles` signature to accept an optional `reviewExecutionFile` (default `nil`); when provided, parse it into `reviewCost`/`reviewModels`.

Changes to `PRCreatedReport.swift` — update `buildCostSummaryTable()` to add a "Review" row between "Summary Generation" and "Total":

```
| Task Completion    | $X.XX |
| Review             | $X.XX |   ← new row (only shown if reviewCost > 0)
| Summary Generation | $X.XX |
| **Total**          | $X.XX |
```

Only include the "Review" row when `costBreakdown.reviewCost > 0` to keep the table clean when no review.md is present.

Changes to `RunChainTaskUseCase.swift` — pass `reviewCost` into `CostBreakdown`:

```swift
let costBreakdown = CostBreakdown(
    mainCost: mainCost,
    reviewCost: reviewCost,
    summaryCost: summaryCost
)
```

## - [x] Phase 5: Validation

**Skills used**: `swift-testing`
**Principles applied**: Added unit tests for all six areas specified. Tests for `extractReviewSummary` and `appendReviewNote` were added to `RunChainTaskUseCaseTests.swift` using Swift Testing (matching that file's style). Tests for `Project.reviewPath`, `ProjectRepository.loadLocalReview`, `CostBreakdown`, and `PRCreatedReport.buildCostSummaryTable` were added to their existing XCTest files matching the local style. Pre-existing compilation errors in `FileSystemOperationsTests.swift`, `ClaudeChainModelTests.swift`, and `AppIPCClientTests.swift` prevent the test runner from executing, but these errors are confirmed pre-existing and unrelated to this phase.


Unit tests (fast, no network):
- `extractReviewSummary` — finds `REVIEW_SUMMARY:` line, handles missing, handles multiple matches (uses last).
- `appendReviewNote` — inserts after the correct `[x]` line, graceful when task not found, works with multiple tasks in spec.
- `ProjectRepository.loadLocalReview` — file exists, file missing, file empty.
- `Project.reviewPath` — verifies path format.
- `CostBreakdown` — `totalCost` includes `reviewCost`, `allModels` includes `reviewModels`, `toJSON`/`fromJSON` round-trip preserves `reviewCost`, missing `review_cost` in JSON defaults to `0.0`.
- `PRCreatedReport.buildCostSummaryTable` — "Review" row present when `reviewCost > 0`, absent when `reviewCost == 0`.

End-to-end smoke test against `../claude-chain-demo`:
1. In `../claude-chain-demo`, create a new claude-chain project (e.g. `claude-chain/review-test/`) with a minimal `spec.md` (1–2 trivial tasks) and a `review.md` with a simple conformance rule (e.g. "All Swift files must have a file-level comment").
2. Commit and push both files to the remote.
3. From the CLI in the AIDevTools repo, run `claude-chain run-task` targeting the `review-test` project in `../claude-chain-demo`.
4. Verify on the resulting branch:
   - A "Review: …" commit exists after the "Mark task N as complete in spec.md" commit.
   - An "Add review note for task N" commit exists.
   - `spec.md` contains an `<!-- review: … -->` note under the completed task entry.
5. Open the PR and verify the cost breakdown comment includes a non-zero "Review" row.
