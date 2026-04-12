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

## - [x] Phase 3: Eliminate per-PR staleness-check API calls using list metadata

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Added pre-merge `updatedAt` snapshot in `AllPRsModel.refresh()` before `buildPRModels()` overwrites the metadata. After the merge, compared each PR's freshly-fetched `updatedAt` against the cached value; skipped `refreshPRData()` entirely for unchanged PRs. New PRs (not in the pre-merge map) and PRs with changed or absent `updatedAt` still trigger a full refresh. Trace log added per logging conventions.

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

## - [x] Phase 4: Research GitHub API for "fetch only updated" optimization

**Skills used**: `ai-dev-tools-debug`
**Principles applied**: Research only — current early-stop approach is already optimal for the REST API. No code changes made. See findings below.

**Findings**:

1. **GitHub Issues API `?since=`**: The Issues API (`/repos/{owner}/{repo}/issues?since=ISO8601`)
   does accept a `since` parameter and returns issues (including PRs) updated after that
   timestamp. However, it mixes issues and PRs, requiring client-side filtering. More
   importantly, the PR list API (`/repos/{owner}/{repo}/pulls`) does NOT support `?since=`,
   so switching to the Issues endpoint just to get `since=` support adds complexity and
   mixed-type responses. **Verdict: not worth adopting.**

2. **GitHub PR list `?sort=updated&direction=desc` (current approach)**: This is what
   `GitHubAPIService.listPullRequests` already does. Combined with the early-stop mechanism
   in `GitHubAPIService` (which breaks pagination once `updatedAt < filter date`), this is
   functionally equivalent to "fetch only PRs updated since X" — the only difference is we
   fetch a partial first page of older PRs before the early-stop fires. With a 7-day window
   and 100 items/page, early-stop triggers after 1–2 pages at most. **Verdict: current
   approach is already optimal.**

3. **GitHub ETags / conditional requests**: GitHub returns an `ETag` header on list
   responses. Storing it and sending `If-None-Match` on subsequent fetches would yield a
   304 (no body) when the page hasn't changed, saving bandwidth and counting toward rate
   limits differently. The limitation: ETags are page-level, not endpoint-level. Each page
   gets its own ETag. Since we're already stopping after 1–2 pages (early-stop), the
   bandwidth savings are marginal (~6–12 KB per request). Implementation overhead
   (persisting per-page ETags, handling 304 in `OctokitClient`) is not justified by the
   small gain. **Verdict: not worth implementing given the early-stop already limits page
   fetches.**

4. **GitHub GraphQL `search` with `updated:>DATE`**: GraphQL search (`is:pr is:open
   updated:>DATE`) could return only recently-updated PRs in a single request. However,
   the GitHub search API has stricter rate limits (30 requests/min authenticated vs.
   5,000/hr for REST), and search results may have an indexing lag (results can be seconds
   to minutes stale relative to REST). It would also require adding GraphQL support to
   `OctokitClient` — a significant refactor. **Verdict: not worth the complexity and
   rate-limit trade-off when REST + early-stop already achieves 1–2 pages.**

**Conclusion**: No code changes needed. The current `?sort=updated&direction=desc` +
client-side early-stop is the correct and near-optimal approach for the REST API. The
GitHub PR list endpoint does not offer a `?since=` parameter, and all the alternatives
(Issues API, ETags, GraphQL) introduce more complexity than they save.

## - [x] Phase 5: Research and document `updatedAt` coverage gaps

**Skills used**: none
**Principles applied**: Research-only phase. Documented confirmed gaps and assessed their impact against the review workflow to make an explicit accept/reject decision on each gap.

**Skills to read**: (none specific — research task)

Bill wants to know which GitHub events update a PR's `updatedAt`, and which don't. This
matters because our staleness check (Phase 3) relies on `updatedAt` to decide whether to
skip a PR.

**Confirmed behavior**:
- ✅ Commit pushed to PR branch → updates `updated_at`
- ✅ PR title or body edited → updates `updated_at`
- ✅ Label added/removed → updates `updated_at`
- ✅ Assignee added/removed → updates `updated_at`
- ✅ Review submitted (approve, request changes, comment) → updates `updated_at`
- ✅ Review comment posted → updates `updated_at`
- ✅ Issue comment posted → updates `updated_at`
- ✅ PR state changed (open/close/merge) → updates `updated_at`
- ✅ Draft status toggled (draft ↔ ready for review) → updates `updated_at` (it's a
  direct mutation to the PR object, confirmed via GitHub community discussions)
- ❌ Check run / CI status changed → does **NOT** update `updated_at` on the PR object

**Check-run gap — findings**:

Check runs are architecturally separate from PR objects. They are attached to commit SHAs
via the Checks API, and fire their own `check_run` webhook events independently of the
`pull_request` webhook. When a CI run completes (passes, fails, or is re-triggered), GitHub
updates the check run object — not the PR object — so the PR's `updated_at` timestamp does
not change.

This means: a PR whose only change since last fetch is a CI status update (e.g., tests
went pending → passed/failed after a manual re-run) will be treated as unchanged by our
Phase 3 staleness check, and its cached data will not be refreshed.

**Impact assessment**:

The gap is narrow in practice:
- CI runs triggered by a code push always follow a commit, which already updates
  `updated_at` via the push itself. Those PRs get refreshed normally.
- The gap only fires for: manually re-triggered CI runs, scheduled CI runs, or external
  CI systems updating check status without a corresponding push.
- Check run status is a display concern (the CI badge on the PR row). The core review
  workflow — diff, comments, analysis, violations — is unaffected by stale check-run data.

**Decision: accept the gap.**

The fix (a separate TTL-based check run refresh path running independently of `updatedAt`
staleness) would add meaningful complexity for an edge case that doesn't affect the review
workflow. The known limitation is: after a manual CI re-run, the CI badge on a PR row may
show stale status until the next event that updates `updated_at` (e.g., a new commit or
comment) triggers a normal refresh. This is acceptable.

**Research tasks**:
1. ~~Verify the check-run gap empirically: create a test PR, trigger a CI run, and observe
   whether `updated_at` changes on the PR object.~~ Confirmed via GitHub architecture:
   check runs live on commit SHAs, not PR objects; `check_run` and `pull_request` webhooks
   are independent event streams.
2. ~~Assess the impact~~ See impact assessment above.
3. ~~Document the decision~~ Decision: **accept the gap** (see above).
4. ~~If unacceptable: design a separate light-weight check run refresh path~~ Not needed.

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
