## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | Layer placement and dependency rules |
| `ai-dev-tools-swift-testing` | Swift Testing conventions |
| `ai-dev-tools-enforce` | Post-implementation standards check |

## Background

PR data is currently loaded through several independent use cases that clients must manually orchestrate. Both PRRadar and Claude Chain implement their own cache-first / per-PR enrichment patterns independently.

**Goal:** build a single `GitHubPRLoaderUseCase` that fetches everything GitHub knows about a set of PRs (list, comments, reviews, check runs) and emits incremental updates as an `AsyncStream`. Then validate it with a new **"Pull Requests" tab** — a clean, feature-agnostic UI that knows nothing about PRRadar or Claude Chain.

This new tab is the foundation. Once it works, PRRadar and Claude Chain migrate to use this architecture in subsequent plans.

**Scope of this plan:**
- Enrich `PRMetadata` with all GitHub-sourced fields
- Build `GitHubPRLoaderUseCase`
- Build a new `PullRequestsModel` that observes the use case
- Build a new "Pull Requests" tab in the app with PR list, review status, and check status indicators
- PRRadar and Claude Chain are **not** migrated here

**Boundary:**
- `GitHubPRLoaderUseCase` owns: PR list loading, per-PR data refresh, comments, reviews, check runs
- No PRRadar-specific or Claude Chain-specific logic anywhere in the new model or UI
- PRRadar-specific use cases (`FetchPRUseCase`, `FetchReviewCommentsUseCase`) are untouched

## Phases

## - [x] Phase 1: Enrich `PRMetadata` and remove dead `Codable`

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-swift-testing`
**Principles applied**: Removed `Codable` from `PRMetadata`/`Author` since disk format is `GitHubPullRequest`; added four optional enrichment fields (`githubComments`, `reviews`, `checkRuns`, `isMergeable`) defaulting to `nil` so no callsites break; implemented custom `Equatable`/`Hashable` on `number` since synthesized conformance can't include non-`Hashable` enrichment fields; added `headRefNamePrefix` to `PRFilter` with prefix-match in `matches(_:)`; reordered `PRFilter.init` parameters alphabetically per project convention and updated all call sites; replaced encode/decode tests with `toPRMetadata()` conversion tests covering required fields, missing-field errors, state mapping, and prefix filtering.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-swift-testing`

**Remove `Codable`:**
- Remove `Codable` from `PRMetadata` and `PRMetadata.Author` — dead in production (disk format is `GitHubPullRequest`; `PRMetadata` is only ever constructed in memory via `toPRMetadata()`)
- Update `PRMetadataTests` — replace encode/decode tests with tests that exercise `GitHubPullRequest.toPRMetadata()` conversion (required fields, missing-field errors, state mapping)

**Add GitHub-sourced fields** (all optional, default `nil`, no existing callsites break):

```swift
public var githubComments: GitHubPullRequestComments?  // comments, reviews, inline review comments
public var reviews: [GitHubReview]?                    // PR review approvals / requests
public var checkRuns: [GitHubCheckRun]?                // CI check results
public var isMergeable: Bool?                          // conflict status
```

- `toPRMetadata()` leaves all four as `nil` — populated by the loader use case
- `PRMetadata.fallback(number:)` — leave all as `nil`

**Add `headRefNamePrefix` to `PRFilter`:**

```swift
public var headRefNamePrefix: String?
```

Update `PRFilter.matches(_:)` to filter out PRs whose `headRefName` does not start with the prefix when set. This is needed for Claude Chain's branch-prefix filtering when it adopts this architecture later.

## - [ ] Phase 2: Build `GitHubPRLoaderUseCase`

**Skills to read**: `ai-dev-tools-architecture`

File: `Sources/Features/PRReviewFeature/usecases/GitHubPRLoaderUseCase.swift`

**Event type:**

```swift
public struct GitHubPRLoaderUseCase {
    public enum Event: Sendable {
        // List-level events
        case listLoadStarted                              // beginning disk cache read
        case cached([PRMetadata])                         // list from disk, no enrichment yet
        case listFetchStarted                             // beginning network list fetch
        case fetched([PRMetadata])                        // network list complete
        case listFetchFailed(String)                      // network list fetch failed

        // Per-PR events
        case prFetchStarted(prNumber: Int)                // beginning one PR's enrichment
        case prUpdated(PRMetadata)                        // one PR complete with all enrichment
        case prFetchFailed(prNumber: Int, error: String)  // one PR failed (others continue)

        // Terminal
        case completed                                    // all PRs processed
    }

    // Full list load — may take 20+ minutes for large repos
    public func execute(filter: PRFilter) -> AsyncStream<Event>

    // Single-PR short-circuit — for manual per-PR refresh
    public func execute(prNumber: Int) -> AsyncStream<Event>
}
```

**Execution sequence inside `execute(filter:)`:**

1. Emit `.listLoadStarted`
2. Load from disk → emit `.cached([PRMetadata])`
3. Emit `.listFetchStarted`
4. Fetch updated list from GitHub → emit `.fetched([PRMetadata])` or `.listFetchFailed`
5. For each changed PR (skip if `updatedAt` unchanged), **sequentially**:
   - Emit `.prFetchStarted(prNumber:)`
   - Fetch `GitHubPullRequest` data + `GitHubPullRequestComments` + `[GitHubReview]` + `[GitHubCheckRun]` + `isMergeable`
   - Construct fully enriched `PRMetadata`
   - Emit `.prUpdated(enrichedMetadata)` or `.prFetchFailed(prNumber:error:)`
6. Emit `.completed`

**Notes:**
- `AsyncStream` (not throwing) — errors surface as events so partial results always reach the observer
- Per-PR loop runs **sequentially** — matches current behavior, avoids GitHub rate limit issues
- No PRRadar-specific or Claude Chain-specific logic

## - [ ] Phase 3: Build `PullRequestsModel`

**Skills to read**: `ai-dev-tools-architecture`

File: `Sources/Apps/AIDevToolsKitMac/PullRequests/Models/PullRequestsModel.swift`

A clean `@Observable @MainActor` model that observes `GitHubPRLoaderUseCase` and exposes state for the UI. No PRRadar or Claude Chain knowledge.

```swift
@Observable
@MainActor
final class PullRequestsModel {

    enum State {
        case uninitialized
        case loading
        case refreshing([PRMetadata])
        case ready([PRMetadata])
        case failed(String, prior: [PRMetadata]?)
    }

    private(set) var state: State = .uninitialized
    private(set) var fetchingPRNumbers: Set<Int> = []

    let config: PRRadarRepoConfig

    func load() async { ... }       // calls execute(filter:), handles all events
    func refresh(number: Int) async { ... }  // calls execute(prNumber:)

    var prs: [PRMetadata]? { ... }  // extracts list from state
}
```

- `fetchingPRNumbers` drives per-row spinners — added on `.prFetchStarted`, removed on `.prUpdated` / `.prFetchFailed`
- No `PRModel`, no summaries, no phase state — just `PRMetadata` and load state

## - [ ] Phase 4: Build "Pull Requests" tab UI

**Skills to read**: `ai-dev-tools-architecture`

New tab named **"Pull Requests"** in the Mac app. Demonstration UI — general GitHub PR data only, no PRRadar or Claude Chain specifics.

Files: `Sources/Apps/AIDevToolsKitMac/PullRequests/Views/`

**PR list view:**
- One row per `PRMetadata`
- Per-row spinner when `prNumber` is in `fetchingPRNumbers`
- Reuse existing components where they fit (author display, PR number badge, state label); create new ones where PRRadar-specific assumptions would leak

**Status indicators per row** (matching the kind of indicators PRRadar shows today):
- Review status: approved / changes requested / pending — derived from `metadata.reviews`
- Build status: passing / failing / pending / conflicting — derived from `metadata.checkRuns` + `metadata.isMergeable`
- Draft indicator
- PR state (open / merged / closed)

**Loading states:**
- Global list spinner while `state == .loading`
- Per-row spinner for PRs in `fetchingPRNumbers`
- Error view when `state == .failed` with no prior data

## - [ ] Phase 5: Validation

**Skills to read**: `ai-dev-tools-enforce`

1. `swift build` — must be clean.
2. `swift test` — all tests pass.
3. Verify `PRMetadata` has no `Codable` conformance.
4. Verify `PRMetadata` has `githubComments`, `reviews`, `checkRuns`, `isMergeable`.
5. Verify `PRFilter` has `headRefNamePrefix` and `matches(_:)` respects it.
6. Verify `PullRequestsModel` has no imports of PRRadar or Claude Chain feature modules.
7. Verify the "Pull Requests" tab renders with per-row review and build status indicators.
8. Verify per-row spinners appear while a PR is being fetched.
9. Run enforce on all modified files.
