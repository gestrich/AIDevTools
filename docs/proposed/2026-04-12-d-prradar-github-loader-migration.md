## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | Layer placement, CLI parity, use case conventions |
| `ai-dev-tools-composition-root` | How CLI and Mac app wire dependencies — commands must use CLICompositionRoot |
| `ai-dev-tools-swift-testing` | Swift Testing conventions for any new test files |
| `ai-dev-tools-enforce` | Post-implementation standards check across all changed files |

## Background

`GitHubPRLoaderUseCase` (built in plan `2026-04-12-c`) provides a single streaming use case that fetches the GitHub PR list, enriches each PR with comments, reviews, check runs, and mergeable status, and emits incremental `AsyncStream<Event>` updates. The new "Pull Requests" tab already uses it via `PullRequestsModel`.

PRRadar still sources its GitHub data through the old stack:
- **Mac:** `AllPRsModel` drives list loading via `FetchPRsUseCase` and per-PR refresh via its own orchestration
- **CLI:** `PRRadarRefreshCommand` uses `FetchPRsUseCase`; `PRRadarRefreshPRCommand` uses `FetchPRUseCase` for single-PR GitHub data

The old stack never fetched reviews or check runs — PRRadar has no visibility into CI status or who approved/requested changes.

**Goal:** Migrate PRRadar's GitHub data sourcing to `GitHubPRLoaderUseCase`. Then surface the enriched data (check run status, review approvals, requested reviewers) in both the Mac UI and CLI. All existing PRRadar functionality — AI pipeline phases, diff view, comment posting, rule evaluation — is preserved unchanged; only the *data source* changes.

**What stays PRRadar-specific (different flow, no change):**
- `reviewComments: [ReviewComment]` on `PRModel` — AI-generated violations from the pipeline, loaded via `FetchReviewCommentsUseCase`. Not GitHub data.
- `comments: CommentPostingState` on `PRModel` — output of `PostCommentsUseCase`. Not GitHub data.
- All pipeline phase state, analysis state, diffs, evaluations — PRRadar-specific, untouched.

**What moves to `PRMetadata` (general GitHub data):**
- `PRModel.postedComments: GitHubPullRequestComments?` is currently a forwarding property to `detail?.postedComments`, which reads GitHub PR comments from a **disk cache** written during sync (`PRDiscoveryService.loadComments()` / `LoadPRDetailUseCase`). After migration, this data lives on `metadata.githubComments` (set live by `GitHubPRLoaderUseCase`). The disk-cache path is replaced.
- `postedCommentCount` in `AnalysisState` is derived from that same disk cache (`postedComments?.reviewComments.count`). After migration it should read `metadata.githubComments?.reviewComments.count`.
- UI callsites: `ReviewDetailView.swift` passes `prModel.postedComments?.comments` to `SummaryPhaseView`; `PRListRow.swift` reads `postedCommentCount` from `analysisState`. Both must be updated to read from `metadata`.

**Scope:**
- `AllPRsModel`: replace `FetchPRsUseCase`-based list loading and per-PR refresh with `GitHubPRLoaderUseCase`
- `PRModel`: remove `postedComments` forwarding property; update `loadSummary()` and `applyDetail()` to derive comment counts from `metadata.githubComments`
- Views: update `ReviewDetailView` and `SummaryPhaseView` to source PR comments from `metadata.githubComments` instead of `prModel.postedComments`
- `PRRadarRefreshCommand` / `PRRadarRefreshPRCommand`: replace with `GitHubPRLoaderUseCase`
- PRListRow and detail view: add check run badge and review status badge using `metadata.checkRuns` / `metadata.reviews`
- `PRRadarStatusCommand` (or `prradar list`): print check run and review summary to stdout

**Not in scope:**
- AI pipeline phases (prepare, analyze, report) — no changes
- Diff view, commit history, inline review comments — still served by `FetchPRUseCase` / `LoadPRDetailUseCase`
- `FetchPRsUseCase`, `FetchPRUseCase`, `LoadPRDetailUseCase` — not deleted; they remain for the pipeline

## Phases

## - [x] Phase 1: Migrate `AllPRsModel` to `GitHubPRLoaderUseCase`

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`
**Principles applied**: Replaced `FetchPRsUseCase`-based `refresh(filter:)` with `GitHubPRLoaderUseCase.execute(filter:)` handling all events; replaced `FetchPRUseCase`-based `refresh(number:)` with `GitHubPRLoaderUseCase.execute(prNumber:)`; removed `gitHubPRService`/`changesTask`/`startObservingChanges` since `GitHubPRLoaderUseCase` subsumes that pipeline; added `fetchingPRNumbers: Set<Int>` for per-row spinner tracking; updated `PRModel.loadSummary()` and `applyDetail()` to derive `postedCount` from `metadata.githubComments` instead of the disk cache; removed `PRModel.postedComments` forwarding property; updated `ReviewDetailView` to read from `prModel.metadata.githubComments`; `loadCached()` (disk-only path used on init and error recovery) is preserved unchanged.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`
**Prior plan to read**: `docs/completed/2026-04-12-c-unified-github-pr-loader.md` — covers `GitHubPRLoaderUseCase` design, event types, and how `PullRequestsModel` consumes it; use this as the reference implementation for `AllPRsModel`'s migration

Replace `AllPRsModel`'s GitHub data loading with `GitHubPRLoaderUseCase`. All PRRadar-specific logic (creating `PRModel` per PR, analysis state, rule evaluation, pipeline phases) stays unchanged.

**File:** `Sources/Apps/AIDevToolsKitMac/PRRadar/Models/AllPRsModel.swift`

**Changes:**
- Remove the `FetchPRsUseCase`-based loading path for the PR list
- Replace with `GitHubPRLoaderUseCase.execute(filter:)` — handle all events:
  - `.cached` → populate `prs` immediately so the list is visible before network completes
  - `.fetched` → update the list with fresh GitHub metadata
  - `.prFetchStarted(prNumber:)` → mark that PR as loading (drives per-row spinners)
  - `.prUpdated(metadata)` → update the corresponding `PRModel`'s metadata (preserves any already-loaded analysis state on `PRModel`)
  - `.prFetchFailed` → log or surface error per the architecture conventions
  - `.completed` → clear loading state
- Replace the per-PR refresh path (currently calling its own orchestration or `FetchPRUseCase` for metadata) with `GitHubPRLoaderUseCase.execute(prNumber:)`
- `AllPRsModel` should NOT construct `GitHubPRLoaderUseCase` inline — inject it via `init` or use the `PRRadarRepoConfig` already held by the model (same pattern as `PullRequestsModel`)
- Preserve all existing `PRModel` creation, selection, and pipeline-triggering logic

**`PRModel` changes:**
- When `.prUpdated(metadata)` arrives, find the matching `PRModel` by PR number and call `updateMetadata(_ metadata: PRMetadata)` (already exists) — this replaces the metadata including `githubComments`, `reviews`, `checkRuns`, `isMergeable` without discarding any analysis/pipeline state.
- Remove the `postedComments` forwarding property (`var postedComments: GitHubPullRequestComments? { detail?.postedComments }`). The forwarding property was reading comments from a disk-cached snapshot written during sync; `metadata.githubComments` now holds the same data, fresher.
- In `loadSummary()`: replace the `PhaseOutputParser.parsePhaseOutput(... filename: PRRadarPhasePaths.ghCommentsFilename)` disk read with `metadata.githubComments?.reviewComments.count ?? 0` for the `postedCount`.
- In `applyDetail()`: replace `newDetail.postedComments?.reviewComments.count` with `metadata.githubComments?.reviewComments.count` for the `postedCount`.
- `reviewComments: [ReviewComment]` (AI violations) and `comments: CommentPostingState` (pipeline posting output) are PRRadar-specific — do not touch.

**View callsite updates:**
- `ReviewDetailView.swift:27`: `prModel.postedComments?.comments ?? []` → `prModel.metadata.githubComments?.comments ?? []`
- `SummaryPhaseView.swift` takes a `postedComments: [GitHubComment]` parameter — the parameter stays, only the value passed from `ReviewDetailView` changes.

**Key constraint:** `FetchPRsUseCase` is not deleted. It may still be used by other callers. Only `AllPRsModel`'s usage is migrated.

## - [ ] Phase 2: Migrate PRRadar CLI Refresh Commands

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`
**Prior plan to read**: `docs/completed/2026-04-12-c-unified-github-pr-loader.md` — see Phase 2 for the full event enum and Phase 5 for CLI parity expectations

Migrate `PRRadarRefreshCommand` and `PRRadarRefreshPRCommand` to stream from `GitHubPRLoaderUseCase`.

**Files:**
- `Sources/Apps/AIDevToolsKitCLI/PRRadar/Commands/PRRadarRefreshCommand.swift`
- `Sources/Apps/AIDevToolsKitCLI/PRRadar/Commands/PRRadarRefreshPRCommand.swift`

**`PRRadarRefreshCommand` (prradar refresh):**
- Replace `FetchPRsUseCase.execute()` call with `GitHubPRLoaderUseCase.execute(filter:)`
- Print streaming progress as events arrive:
  - `.listLoadStarted` → "Loading cached PRs..."
  - `.cached(prs)` → "Loaded \(prs.count) PRs from cache"
  - `.listFetchStarted` → "Fetching from GitHub..."
  - `.fetched(prs)` → "Fetched \(prs.count) PRs"
  - `.prFetchStarted(number)` → "Enriching PR #\(number)..."
  - `.prUpdated(metadata)` → "  #\(metadata.number) \(metadata.title)"
  - `.prFetchFailed(number, error)` → stderr: "Failed PR #\(number): \(error)"
  - `.completed` → "Done."
- Use `CLICompositionRoot.create(...)` for credentials — do not construct `GitHubPRLoaderUseCase` inline

**`PRRadarRefreshPRCommand` (prradar refresh-pr):**
- Replace current GitHub data fetch path with `GitHubPRLoaderUseCase.execute(prNumber:)`
- Print the same per-PR progress events as above
- Note: this command may also trigger a sync/pipeline step after the metadata refresh — preserve that behavior; only the metadata-fetch portion is migrated

## - [ ] Phase 3: Add Check Run & Review Indicators to PRRadar Mac UI

**Skills to read**: `ai-dev-tools-architecture`

Surface `PRMetadata.checkRuns` and `PRMetadata.reviews` in the PRRadar PR list and detail view. The data is already fetched by `GitHubPRLoaderUseCase` and stored on `PRMetadata` — this phase just renders it.

**PRListRow (`Sources/Apps/AIDevToolsKitMac/PRRadar/Views/PRListRow.swift`):**

Add two new badge indicators to each row, consistent with the existing state/analysis badges:

1. **Build status badge** — derived from `metadata.checkRuns`:
   - Passing: all check runs have `isPassing == true`
   - Failing: any check run has `isFailing == true`
   - Pending: any check run is `in_progress` or `queued`
   - No badge: `checkRuns == nil` (not yet loaded)
   - Conflicting: `isMergeable == false` overrides (matches Pull Requests tab convention)

2. **Review status badge** — derived from `metadata.reviews`:
   - Approved: at least one `APPROVED` and none `CHANGES_REQUESTED`
   - Changes requested: at least one `CHANGES_REQUESTED`
   - Pending review: reviews array present but no approvals or change requests
   - No badge: `reviews == nil`

Keep the derivation logic private to the row view (same approach used in `PullRequestsRowView`). Do not promote these to public types unless a second callsite exists.

**Detail view — review section (`Sources/Apps/AIDevToolsKitMac/PRRadar/Views/SummaryPhaseView.swift` or a new `ReviewStatusView`):**

Add a section in the PR detail that shows:
- Requested reviewers: list of reviewer logins from `reviews` where `state == .pending`
- Approvals: list of reviewer logins who approved
- Change requests: list of reviewer logins who requested changes
- Check run results: name and status/conclusion for each `GitHubCheckRun`

If `reviews == nil` or `checkRuns == nil`, show a "Loading..." placeholder (cleared once `AllPRsModel` emits an update for that PR).

## - [ ] Phase 4: Add Check Run & Review Info to PRRadar CLI

**Skills to read**: `ai-dev-tools-architecture`

Update `PRRadarStatusCommand` (or `prradar list` if more appropriate after reviewing those files) to include check run and review summary in its output.

**File:** `Sources/Apps/AIDevToolsKitCLI/PRRadar/Commands/PRRadarStatusCommand.swift`

Add to the per-PR status output:
- **Reviews:** `Approved by: @alice` / `Changes requested by: @bob` / `Review pending: @charlie`
- **Checks:** `Checks: ✓ passing` / `✗ 2 failing` / `⏳ pending`

If `metadata.reviews` or `metadata.checkRuns` is `nil` (cache not yet enriched), print `(not loaded — run prradar refresh-pr <number>)` rather than silently omitting.

For the list output (if `PRRadarRefreshCommand` prints a summary table), add short review/check columns alongside existing state columns so both are visible at a glance.

## - [ ] Phase 5: Validation + Enforce

**Skills to read**: `ai-dev-tools-enforce`

1. `swift build` — must be clean with no warnings.
2. `swift test` — all existing tests pass.
3. Manual smoke-check:
   - Run `prradar refresh` → confirm streaming progress output, confirm reviews and check runs appear in the final status line
   - Run `prradar refresh-pr <number>` → confirm single-PR enrichment
   - Launch Mac app → open PRRadar tab → confirm list shows build + review badges → select a PR → confirm review and check run section in detail view
4. Confirm `FetchPRsUseCase` is still present and compiles (not deleted).
5. Confirm `AllPRsModel` no longer directly calls `FetchPRsUseCase` for list loading.
6. Run `ai-dev-tools-enforce` (Fix mode) on all Swift files changed during this plan.
