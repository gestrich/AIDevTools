## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-debug` | CLI commands and log paths for investigating runtime behavior |
| `ai-dev-tools-logging` | How to add trace logging and read logs to diagnose timing issues |
| `ai-dev-tools-architecture` | Layer placement and dependency rules to keep fixes in the right place |
| `ai-dev-tools-enforce` | Post-implementation standards check |

## Background

When opening the PR list view, Bill sees three sequential slowdowns:

1. **~10 seconds of blank screen** before any cached PRs appear
2. **~5 seconds of an unclear spinner** above the list after PRs first appear
3. **Per-PR spinners** as each PR refreshes one at a time

Additionally, Bill wants to ensure we are being smart about when we refetch cached PR data
(using `updatedAt` staleness checks), and wants us to research whether GitHub offers any
"fetch only PRs updated since X" API optimization.

The root cause of issue #1 was identified by code inspection: `buildPRModels()` calls
`loadSummary()` sequentially for every PR before the state is ever set to `.ready()`.
`loadSummary()` does disk I/O per PR (reads JSON files, resolves commit hashes, reads
directory listings). With 20–50 PRs in a 7-day window, this serializes into several
seconds of disk work before the user sees anything.

## Phases

## - [x] Phase 1: Show cached PR list immediately (fix the ~10s blank screen)

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-logging`
**Principles applied**: Separated model construction from summary loading. `buildPRModels()` is now synchronous and returns models immediately without blocking on disk I/O. `discoverAndMerge()` and `refresh()` both set `state = .ready(models)` before summary loading begins. A new `loadSummariesInBackground(for:)` helper fires a `Task` with `withTaskGroup` so all PR summary loads interleave at suspension points rather than running serially. Trace logging added at summary load start/finish per logging conventions.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-logging`

**Root cause**: In `AllPRsModel.buildPRModels(from:reusingExisting:)`, `loadSummary()` is
called sequentially for each PR inside an `async` loop before the method returns. Since
`discoverAndMerge()` awaits `buildPRModels()` before setting `state = .ready(models)`,
the list doesn't appear until every PR's summary badges have loaded from disk.

**Fix**: Separate model construction from summary loading:

1. In `buildPRModels()`, build all `PRModel` instances without calling `loadSummary()`
2. Return the models immediately
3. In `discoverAndMerge()`, set `state = .ready(models)` right after building models
4. Then kick off summary loading concurrently in a detached background task using
   `withTaskGroup` so all PRs load in parallel rather than serially

Expected outcome: The cached PR list appears in under a second. Summary badges (violation
count, comment count) populate shortly afterward as background tasks complete.

**Note**: `loadSummary()` is also called from `buildPRModels()` during the post-refresh
`buildPRModels(from:reusingExisting:)` call in `refresh()`. Apply the same pattern there —
don't block the list update on badge loading.

## - [x] Phase 2: Clarify the post-list-load spinner (the ~5s "what is it doing?" pause)

**Skills used**: `ai-dev-tools-debug`, `ai-dev-tools-logging`
**Principles applied**: Added trace logging (`Logger(label: "FetchPRListUseCase")`) measuring end-to-end duration and fetched PR count. Added trace logging to `GitHubAPIService.listPullRequests` logging each page fetch, early-stop trigger, and final page/total summary — confirming the date-filter early-stop is wired end-to-end. Updated `RefreshAllState.progressText` to return `"Fetching…"` when `total == 0` so the toolbar button shows a human-readable label during the GitHub API phase instead of a bare spinner.

**Skills to read**: `ai-dev-tools-debug`, `ai-dev-tools-logging`

After Phase 1, the list appears quickly from cache. Then `refresh()` runs, setting state
to `.refreshing(prior)` while `FetchPRListUseCase` calls the GitHub API to get the fresh
PR list. This is the ~5-second pause.

**Research**: Add trace logging (if not already present) to measure:
- How long `FetchPRListUseCase.execute()` takes end-to-end
- How many GitHub API pages are fetched (should now be fewer due to date filter passthrough)

**Fix**:
1. Verify the date filter passthrough from the last commit is actually reducing pages.
   With a 7-day window and PRs sorted by `updated_at` desc, the early-stop should fire
   after 1–2 pages instead of fetching all open PRs.
2. Make the spinner's purpose clear to the user. The `refreshAllState` already has a
   progress text mechanism. Ensure the view surfaces "Fetching from GitHub..." in the
   filter bar or toolbar during this phase rather than showing a cryptic spinner.
3. If timing is still poor after the date filter fix, document the minimum latency (one
   GitHub API round-trip) and note it cannot be eliminated without a cache-first approach.

## - [ ] Phase 3: Eliminate per-PR staleness-check API calls using list metadata

**Skills to read**: `ai-dev-tools-architecture`

After `refresh()` fetches the PR list, it loops through each PR and calls
`pr.refreshPRData()` → `SyncPRUseCase.execute()`. That use case checks staleness by
calling `gitHub.getPRUpdatedAt(number:)` — a separate API call per PR — then comparing
against the cached `updatedAt`.

**The optimization**: We just fetched the PR list, which already contains fresh `updatedAt`
for every PR. There's no need to make another API call per PR to check staleness.

**Fix**:
1. After `FetchPRListUseCase` completes, `refresh()` has the fresh `[PRMetadata]`. Each
   `PRMetadata` has `updatedAt`.
2. For each PR in the refresh loop, compare `pr.metadata.updatedAt` (just updated from the
   list fetch) against the PR's previously-cached `updatedAt` (stored before `buildPRModels`
   merges in the new metadata).
3. If `updatedAt` is unchanged, skip `refreshPRData()` entirely — no API call needed.
4. If `updatedAt` changed, call `refreshPRData()` as before.

This requires capturing the pre-merge `updatedAt` values before `buildPRModels` overwrites
them with fresh metadata. Save them as a `[Int: String]` (prNumber → updatedAt) before
the merge, then compare during the loop.

Expected outcome: PRs that haven't changed since the last fetch are skipped entirely,
making the per-PR refresh loop much faster on typical refreshes.

## - [ ] Phase 4: Research GitHub API for "fetch only updated" optimization

**Skills to read**: `ai-dev-tools-debug`

Bill wants to know if GitHub offers a `?since=` or similar parameter that lets us skip
PRs unchanged since the last fetch at the API level.

**Research tasks**:

1. **GitHub Issues API `?since=`**: The Issues API (`/repos/{owner}/{repo}/issues`) does
   accept `?since=ISO8601` and returns issues (including PRs) updated after that timestamp.
   Investigate whether this is usable as a PR list source.

2. **GitHub PR list `?sort=updated&direction=desc`**: This is what we currently use. Combined
   with the early-stop mechanism (stop paginating once `updatedAt < since`), this is
   effectively equivalent to "fetch only updated PRs" for our use case. Document whether
   this is sufficient.

3. **GitHub ETags / conditional requests**: GitHub supports `If-None-Match` / `If-Modified-Since`
   headers. A 304 response would mean the result hasn't changed since the last fetch.
   However, this only helps at the page level, not per-PR. Investigate whether ETags are
   worth implementing for the PR list endpoint.

4. **GitHub GraphQL `search` with `updated:>DATE`**: GraphQL search supports date filters.
   Could be a cleaner way to fetch only recently-updated PRs with a single request.

Document the findings and implement any optimization that is both safe and meaningfully
faster. If the current early-stop approach is already optimal, document that conclusion.

## - [ ] Phase 5: Research and document `updatedAt` coverage gaps

**Skills to read**: (none specific — research task)

Bill wants to know which GitHub events update a PR's `updatedAt`, and which don't. This
matters because our staleness check (Phase 3) relies on `updatedAt` to decide whether to
skip a PR.

**Known behavior** (from GitHub docs and common knowledge):
- ✅ Commit pushed to PR branch → updates `updated_at`
- ✅ PR title or body edited → updates `updated_at`
- ✅ Label added/removed → updates `updated_at`
- ✅ Assignee added/removed → updates `updated_at`
- ✅ Review submitted (approve, request changes, comment) → updates `updated_at`
- ✅ Review comment posted → updates `updated_at`
- ✅ Issue comment posted → updates `updated_at`
- ✅ PR state changed (open/close/merge) → updates `updated_at`
- ❓ Check run / CI status changed → **may NOT update `updated_at`**
- ❓ Draft status toggled → verify

**Research tasks**:
1. Verify the check-run gap empirically: create a test PR, trigger a CI run, and observe
   whether `updated_at` changes on the PR object.
2. Assess the impact: if check runs don't update `updated_at`, PRs whose only change is
   CI status will appear stale in our cache until another event triggers a refresh.
3. Document the decision: is this gap acceptable? Check run status is a display concern
   (CI badge on the PR row). The core review workflow (diff, comments, analysis) is not
   affected by stale check run data. If acceptable, document the known limitation.
4. If unacceptable: design a separate light-weight check run refresh path that runs
   independently of `updatedAt` staleness — e.g., refresh check runs for open PRs on a
   short TTL without re-fetching full PR data.

## - [ ] Phase 6: Validation

**Skills to read**: `ai-dev-tools-enforce`

1. Run `swift build` from `AIDevToolsKit/` — must be clean.
2. Run `swift test` — all tests must pass.
3. Manual smoke test:
   - Open the Mac app to the PR list view with a repo configured
   - Verify the PR list appears within ~1 second (cached data, no blank screen)
   - Verify summary badges populate shortly after without re-loading the whole list
   - Verify the refresh spinner has a clear label and completes faster for a 7-day window
   - Verify PRs unchanged since last fetch don't trigger individual refresh spinners
4. Run enforce on all modified files.
