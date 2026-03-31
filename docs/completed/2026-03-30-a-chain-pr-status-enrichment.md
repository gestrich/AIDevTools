## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture (Apps, Features, Services, SDKs) with dependency rules and use case patterns |
| `ai-dev-tools-debug` | CLI commands, project paths, and debugging for AIDevTools |
| `pr-radar-debug` | PRRadar internals and Mac app debugging — useful since ClaudeChain now shares PRRadar's GitHub layer |

## Background

This plan supersedes `docs/proposed/2026-03-29-a-chain-pr-status-enrichment.md`, which is now out of date.

The completed `2026-03-30-a-github-pr-cache-service.md` plan created a shared `GitHubPRService` (in the `GitHubService` module, Services layer) that owns all GitHub PR metadata caching. PRRadar already migrated to use it. `ClaudeChainFeature` was also wired up as a dependent of `GitHubService` in that plan, making `GitHubPRServiceProtocol` directly injectable into ClaudeChain use cases.

The goal of this plan is to bring per-task GitHub enrichment into ClaudeChain — both the CLI `status` command and the Mac app detail view — using the existing shared GitHub layer instead of building a separate GitHub client in ClaudeChain. Both PRRadar and ClaudeChain use `GitHubPRServiceProtocol` as their only GitHub dependency — `GitHubAPIServiceProtocol` is an internal implementation detail of `GitHubPRService` and is not exposed to feature use cases.

The enriched data we want to show per task:
- Which tasks have open PRs (with PR number, URL, age)
- PR review state: approved reviewers, pending reviewers
- PR build/CI status: passing, failing, pending (with check names)
- Draft vs ready-for-review indication
- Merge conflict detection
- Actionable indicators (draft PRs needing promotion, stale PRs, failing CI, no reviewers assigned)

**Data flow**: `GetChainDetailUseCase` (Features layer) will:
1. Use `ListChainsUseCase` to get the local `ChainProject`
2. Use `PRService.getOpenPrsForProject()` (ChainService) to find open PR numbers for the project by branch prefix
3. For each PR number, call `gitHubPRService.pullRequest(number:useCache:true)` — cached PR metadata
4. For each PR, call `gitHubPRService.reviews(number:useCache:false)`, `gitHubPRService.checkRuns(number:useCache:false)`, `gitHubPRService.isMergeable(number:)` — all through the same service
5. Match PRs to tasks via `taskHash`, build enriched types, generate action items

**Key design decisions**:
- `GitHubPRServiceProtocol` is extended with review/check methods; `GitHubPRService` implements them by delegating to `GitHubAPIServiceProtocol` internally and optionally caching results in new `gh-reviews.json` / `gh-checks.json` files in the existing per-PR cache directory
- `GitHubAPIServiceProtocol` is extended with the underlying API calls for reviews/checks, but it remains an internal service detail — use cases never see it
- New shared GitHub types (`GitHubReview`, `GitHubCheckRun`) go in `PRRadarModelsService` since both PRRadar and ClaudeChain can use them
- Chain-specific enrichment types (`ChainProjectDetail`, `EnrichedChainTask`, etc.) stay in `ClaudeChainService`
- The Apps layer (composition root) wires only `GitHubPRService` into `GetChainDetailUseCase` — same as PRRadar

**Original plan's OctoKit proposal is now obsolete**: `OctokitSDK` already exists and is already used by `GitHubService`. ClaudeChain does not add its own GitHub client.

## Phases

## - [x] Phase 1: Add `isDraft` to `GitHubPullRequest` and new shared GitHub types

**Skills used**: `swift-architecture`
**Principles applied**: Changed `isDraft: Bool?` to `isDraft: Bool` with `CodingKeys` mapping to `"draft"` and custom `init(from:)` defaulting to `false` when absent. Kept the existing `GitHubReview` struct intact (already used by PRRadar for PR comments) and added `GitHubReviewState` alongside it. Added `GitHubCheckRun` with computed `isPassing`/`isFailing` properties. Updated `OctokitMapping.swift` to use `draft ?? false` for the non-optional field.

**Skills to read**: `swift-architecture`

`GitHubPullRequest` in `PRRadarModelsService` lacks `isDraft`. Add it so both PRRadar and ClaudeChain can use it.

- Add `isDraft: Bool` to `GitHubPullRequest` with `CodingKeys` mapping to `"draft"` (GitHub API field name). Default to `false` if absent.
- Add `GitHubReview` struct to `PRRadarModelsService`:
  - `author: String` (login)
  - `state: GitHubReviewState` — enum: `.approved`, `.changesRequested`, `.commented`, `.dismissed`, `.pending`
- Add `GitHubCheckRun` struct to `PRRadarModelsService`:
  - `name: String`
  - `status: String` (e.g., `"completed"`, `"in_progress"`, `"queued"`)
  - `conclusion: String?` (e.g., `"success"`, `"failure"`, `"neutral"`, `"cancelled"`)
  - Computed `isPassing: Bool` — `conclusion == "success"`
  - Computed `isFailing: Bool` — `conclusion == "failure"`

Both types are `Codable`, `Sendable`.

## - [x] Phase 2: Add enrichment models to `ClaudeChainService`

**Skills used**: `swift-architecture`
**Principles applied**: Moved `ChainTask` and `ChainProject` from `ClaudeChainFeature` to `ClaudeChainService` (they are plain data models, not orchestration), added `PRRadarModelsService` as a `ClaudeChainService` dependency, used `PRRadarModelsService.GitHubPullRequest` explicitly in `EnrichedPR` to avoid ambiguity with the existing local `GitHubPullRequest` type. Added `import ClaudeChainService` to App-layer files that reference these now-relocated types.

**Skills to read**: `swift-architecture`

Add new domain models to `ClaudeChainService` that represent enriched GitHub state for chain tasks. These extend the existing chain domain, so they live in `ClaudeChainService` alongside `GitHubPullRequest`-aware types.

New file(s) in `ClaudeChainService`:

- **`PRReviewStatus`** struct:
  - `approvedBy: [String]`
  - `pendingReviewers: [String]`

- **`PRBuildStatus`** enum:
  - `.passing`
  - `.failing(checks: [String])`
  - `.pending(checks: [String])`
  - `.conflicting`
  - `.unknown`

- **`EnrichedPR`** struct:
  - `pr: GitHubPullRequest`
  - `isDraft: Bool` (mirrors `pr.isDraft`)
  - `reviewStatus: PRReviewStatus`
  - `buildStatus: PRBuildStatus`
  - `ageDays: Int` — computed from `pr.createdAt`

- **`EnrichedChainTask`** struct:
  - `task: ChainTask`
  - `enrichedPR: EnrichedPR?`

- **`ChainActionKind`** enum:
  - `.draftNeedsReview`
  - `.ciFailure`
  - `.mergeConflict`
  - `.stalePR` (open > 7 days with no activity)
  - `.needsReviewers`

- **`ChainActionItem`** struct:
  - `kind: ChainActionKind`
  - `prNumber: Int`
  - `message: String`

- **`ChainProjectDetail`** struct:
  - `project: ChainProject`
  - `enrichedTasks: [EnrichedChainTask]`
  - `actionItems: [ChainActionItem]`

## - [x] Phase 3: Extend `GitHubPRServiceProtocol` and `GitHubPRService` with review/check support

**Skills used**: `swift-architecture`
**Principles applied**: Added four methods to `GitHubAPIServiceProtocol` and three to `GitHubPRServiceProtocol` (public-facing). Extended `GitHubPRCacheService` with read/write pairs for `gh-reviews.json` and `gh-checks.json`. Implemented `listReviews` via OctoKit (same client already used in `getPullRequestComments`) and `requestedReviewers`/`checkRuns`/`isMergeable` via `gh` CLI (`gh pr view`/`gh pr checks`). Added `GitHubServiceError.ghCommandFailed` for CLI failures. `isMergeable` always fetches live (no caching) since merge state changes frequently.

**Skills to read**: `swift-architecture`

Extend the public service protocol with review and check-run methods so that any use case (ClaudeChain or PRRadar) can fetch this data through the same single service dependency. The raw API calls remain internal to the service.

**Extend `GitHubAPIServiceProtocol`** (internal, in `GitHubService`) with the underlying API calls:
```swift
func listReviews(owner: String, repo: String, prNumber: Int) async throws -> [GitHubReview]
func requestedReviewers(owner: String, repo: String, prNumber: Int) async throws -> [String]
func checkRuns(owner: String, repo: String, prNumber: Int) async throws -> [GitHubCheckRun]
func isMergeable(owner: String, repo: String, prNumber: Int) async throws -> Bool?
```

**Implement in `PRRadarCLIService`'s `GitHubService.swift`**:
- `listReviews`: OctoKit `Octokit().listReviews(session:owner:repository:pullRequestNumber:)`
- `requestedReviewers`: OctoKit `readPullRequestRequestedReviewers`
- `checkRuns`: `gh pr checks <number> --json name,status,conclusion --repo {owner}/{repo}` — parse JSON into `[GitHubCheckRun]`
- `isMergeable`: `gh pr view <number> --json mergeable --repo {owner}/{repo}` — parse `mergeable` field

**Extend `GitHubPRCacheService`** (actor, in `GitHubService`) with storage for the new data:
- `readReviews(number:) throws -> [GitHubReview]?` — reads `gh-reviews.json`
- `writeReviews(_:number:) throws`
- `readCheckRuns(number:) throws -> [GitHubCheckRun]?` — reads `gh-checks.json`
- `writeCheckRuns(_:number:) throws`

**Extend `GitHubPRServiceProtocol`** (public, in `GitHubService`):
```swift
func reviews(number: Int, useCache: Bool) async throws -> [GitHubReview]
func checkRuns(number: Int, useCache: Bool) async throws -> [GitHubCheckRun]
func isMergeable(number: Int) async throws -> Bool?
```

**Implement in `GitHubPRService`**:
- `reviews(number:useCache:)`: returns cached `gh-reviews.json` if `useCache && cache has data`, else fetches via API protocol, writes to cache, emits change
- `checkRuns(number:useCache:)`: same pattern with `gh-checks.json`
- `isMergeable(number:)`: always live (merge state changes frequently and isn't worth caching); delegates directly to the API protocol

`GitHubPRService` already holds `owner` and `repo` (or derives them from its injected configuration), so the use case does not need to pass them explicitly.

## - [x] Phase 4: Create `GetChainDetailUseCase` in `ClaudeChainFeature`

**Skills used**: `swift-architecture`
**Principles applied**: Implemented `GetChainDetailUseCase` as a `struct` conforming to `UseCase` with a single injected dependency (`gitHubPRService: any GitHubPRServiceProtocol`). Used `RepositoryService` to derive the repo string from `repoPath`, `ListChainsUseCase` for local project data, and `PRService` for open PR discovery. Fetched PR details, reviews, check runs, and mergeability concurrently via `withThrowingTaskGroup`. Matched PRs to tasks by parsing `headRefName` with `BranchInfo.fromBranchName` and comparing to `generateTaskHash(task.description)`. Action items generated from enriched PR state per the spec rules.

**Skills to read**: `swift-architecture`

Create the single entry point both the CLI and Mac app call to get enriched chain data.

**`GetChainDetailUseCase`**:
- Input: `Options(repoPath: URL, projectName: String)`
- Output: `ChainProjectDetail`
- Dependencies injected:
  - `gitHubPRService: GitHubPRServiceProtocol` — only GitHub dependency; owns PR metadata, reviews, check runs
  - `chainService` (or direct chain SDK) — for local chain data and `getOpenPrsForProject`

**Flow**:
1. Call `ListChainsUseCase` (or directly `ChainService`) to get the local `ChainProject` for `projectName`
2. Call `PRService.getOpenPrsForProject(projectName:repoPath:)` to get open PR numbers for this chain
3. For each PR number, concurrently fetch via `TaskGroup`:
   - `gitHubPRService.pullRequest(number:useCache:true)`
   - `gitHubPRService.reviews(number:useCache:false)`
   - `gitHubPRService.checkRuns(number:useCache:false)`
   - `gitHubPRService.isMergeable(number:)`
4. Build `PRReviewStatus` from reviews (approved logins + requested reviewer logins from the PR itself)
5. Build `PRBuildStatus` from check runs and mergeable state
6. Build `EnrichedPR` per PR
7. Match PRs to `ChainTask` entries via `taskHash` (existing branch-name → hash → task mechanism)
8. Build `[EnrichedChainTask]` and `[ChainActionItem]` (scan for: draft PRs, failing CI, merge conflicts, stale PRs, PRs with no reviewers)
9. Return `ChainProjectDetail`

**Action item generation rules**:
- `.draftNeedsReview`: `pr.isDraft == true`
- `.ciFailure`: `buildStatus` is `.failing`
- `.mergeConflict`: `buildStatus` is `.conflicting`
- `.stalePR`: `ageDays > 7` and no approved reviews
- `.needsReviewers`: `reviewStatus.pendingReviewers.isEmpty && reviewStatus.approvedBy.isEmpty`

## - [x] Phase 5: Update `ClaudeChainModel` and Mac UI detail view

**Skills used**: `swift-architecture`
**Principles applied**: Added `chainDetails`, `chainDetailLoading`, `gitHubPRService`, and `changesTask` to `ClaudeChainModel` following the `AllPRsModel` observation pattern. Injected `DataPathsService` into the model init so it can compute the GitHub cache URL from repo slug. `loadChains(for:credentialAccount:)` stores the credential account and resets GitHub state on repo change. `loadChainDetail` creates `GitHubPRService` lazily via `GitHubServiceFactory` on first call, then stores and reuses it. `startObservingChanges` watches the service's change stream and force-refreshes affected projects. View changes: `ChainProjectRow` shows an orange action count badge; `ChainProjectDetailView` adds a `.task(id:)` to trigger enrichment load, a GitHub loading indicator, an action items banner, per-task PR indicators (PR link+age, review state, build state, draft badge), and a "Refresh GitHub" button.

**Skills to read**: `swift-architecture`

Update the Mac app to fetch and display enriched data when a chain project is selected, following the same patterns as `AllPRsModel` and `PRModel`.

**`ClaudeChainModel` changes**:

- Add `chainDetails: [String: ChainProjectDetail]` (keyed by project name) — one entry per project that has been enriched. A dictionary, not a single optional, so navigating away and back to a project doesn't re-fetch unnecessarily.
- Add `chainDetailLoading: Set<String>` — tracks which projects are currently fetching enrichment; prevents double-firing.
- Add `gitHubPRService: (any GitHubPRServiceProtocol)?` and `changesTask: Task<Void, Never>?` — mirrors `AllPRsModel`'s observation wiring.
- Add `loadChainDetail(projectName:repoPath:)`:
  - Guard: skip if `chainDetailLoading.contains(projectName)` — already in flight
  - Guard: skip if `chainDetails[projectName] != nil` and not explicitly refreshing — already loaded
  - Insert into `chainDetailLoading`, call `GetChainDetailUseCase`, store result in `chainDetails[projectName]`, remove from `chainDetailLoading`
- Add `startObservingChanges(service:)` — same pattern as `AllPRsModel.startObservingChanges(service:)`:
  - Cancels any prior `changesTask`
  - Starts a `Task` iterating `service.changes()`
  - When a PR number emits, find any loaded `ChainProjectDetail` that contains that PR number and call `loadChainDetail` for that project (force re-fetch) so the enriched state updates live
- Wire `GetChainDetailUseCase` with the `GitHubPRService` from the Apps composition root — same instance already used for PRRadar. Call `startObservingChanges(service:)` once the service is available (e.g., after first `loadChains` completes).

**Loading order** (mirrors PRRadar's two-level pattern):
1. Project selection → call `loadChains` (fast, local) → `state = .loaded(projects)` — list appears immediately
2. Simultaneously trigger `loadChainDetail` for the selected project → enrichment overlays once ready
3. Spinner in the detail view while `chainDetailLoading.contains(selectedProject.name)` is true

**View changes** (`ClaudeChainView.swift`):

In `ChainProjectDetailView`:
- Show a loading spinner or "Loading GitHub data…" indicator while `model.chainDetailLoading.contains(project.name)`
- Show an action items banner at the top when `actionItems` is non-empty (e.g., "2 draft PRs need review", "1 CI failure")
- In the task list, for tasks with a linked `EnrichedPR` show:
  - PR number as a clickable link (opens in browser) with age badge (e.g., "3d")
  - Review indicator: green checkmark for approved, yellow dot for pending review, gray for no reviewers
  - Build indicator: green checkmark for passing, red X for failing, yellow for pending, red conflict icon for merge conflicts
  - Draft badge if `isDraft`
- Add a "Refresh GitHub" button in the header bar that clears `chainDetails[project.name]` and re-calls `loadChainDetail`

In `ChainProjectRow` (sidebar):
- Read `model.chainDetails[project.name]?.actionItems` — show a small orange badge with count if non-empty, only visible once loaded

## - [x] Phase 6: Update CLI `status` command

**Skills used**: `swift-architecture`
**Principles applied**: Changed `StatusCommand` from `ParsableCommand` to `AsyncParsableCommand` to support async GitHub calls. Added `--github`/`-g` flag; without it, behavior is unchanged (local-only, fast). With `--github`, `makeGitHubPRService` follows the same factory pattern as `ClaudeChainModel` — uses `GitHubServiceFactory.create()` to parse the remote URL, derives the normalized slug from `gitHub.repoSlug`, and creates `GitHubPRService` with the Desktop cache directory. `GetChainDetailUseCase` is then instantiated per invocation. Single-project view shows per-task PR indicators inline; list view shows action-count badges. Added `DataPathsService`, `GitHubService`, and `PRRadarCLIService` to `ClaudeChainCLI` Package.swift dependencies.

**Skills to read**: `swift-architecture`

Update `StatusCommand` to accept a `--github` flag (`-g`) that fetches enriched data via `GetChainDetailUseCase`. Without the flag, behavior is unchanged (fast, local-only).

With `--github`:

**Single project detail view**:
```
  task description
  task description  PR #19345 (3d) ✅ Build  👤 bill approved
  task description  PR #19350 (1d) ❌ Build  ⏳ Pending review: nati
  [DRAFT] task description  PR #19360 (0d) ⚠️ Needs review promotion
```

**All-projects list view**:
```
project-name  [████░░░░]  5/10  ⚠ 2 actions needed
```

After the task list, show an "Action Items" section.

Wire `GetChainDetailUseCase` using the same injected services as the Mac app. The repo owner/repo is derived from the `--repo-path` argument via git remote parsing (no separate `--repo` flag needed).

## - [x] Phase 7: Validation

**Skills used**: `ai-dev-tools-debug`, `pr-radar-debug`
**Principles applied**: Created `enrichment-test` chain in `claude-chain-demo` with 3 tasks; opened 2 draft PRs manually (push via `gh` since subprocess git auth differs). Fixed two bugs found during validation: (1) `StatusCommand.makeGitHubPRService` picked the first alphabetical credential account (`bill_jepp`) instead of the repo-owner-matched account (`gestrich`) — fixed to prefer account matching the remote owner; (2) `GitHubService.checkRuns` used unsupported `gh pr checks` fields (`status`, `conclusion`) — updated to use `state` field and handle "no checks reported" exit by returning empty array. Both CLI builds (`ClaudeChainMain`, `AIDevToolsKitMac`) compile cleanly. GitHub cache verified at `~/Library/Application Support/AIDevTools/github/gestrich-claude-chain-demo/` with `gh-pr.json`, `gh-reviews.json`, `gh-checks.json` per PR.

**Skills to read**: `ai-dev-tools-debug`, `pr-radar-debug`

Primary test repo: `/Users/bill/Developer/personal/claude-chain-demo` (remote: `gestrich/claude-chain-demo`). This is a dedicated demo repo with simple chain projects — safe to create new chains and run tasks freely without affecting real work.

### Step 1: Build

```bash
cd AIDevToolsKit
swift build --target claude-chain
swift build --target AIDevToolsKitMac
```

Both targets must compile cleanly.

### Step 2: Prepare a test chain in claude-chain-demo

The repo already has `async-test` (1/4 complete) and `hello-world` (4/5 complete). Create a new chain specifically for this validation so we control which PRs are open:

1. Create `claude-chain-demo/claude-chain/enrichment-test/spec.md` with 3 simple tasks (e.g., create `enrichment-test/file-1.txt`, `enrichment-test/file-2.txt`, `enrichment-test/file-3.txt`)
2. Run two tasks to get two real open PRs against `gestrich/claude-chain-demo`:
   ```bash
   swift run claude-chain run-task --repo-path /Users/bill/Developer/personal/claude-chain-demo enrichment-test
   swift run claude-chain run-task --repo-path /Users/bill/Developer/personal/claude-chain-demo enrichment-test
   ```
3. Confirm two PRs are open on GitHub: `gh pr list --repo gestrich/claude-chain-demo`

### Step 3: CLI — local-only (no regression)

```bash
swift run claude-chain status --repo-path /Users/bill/Developer/personal/claude-chain-demo
```

Output must show all three projects with progress bars. No GitHub calls. Completes instantly.

### Step 4: CLI — enriched output

```bash
swift run claude-chain status --github --repo-path /Users/bill/Developer/personal/claude-chain-demo enrichment-test
```

Expected output for `enrichment-test`:
- Two tasks show linked PR numbers with age badge
- Review indicator shown (likely "no reviewers" initially)
- Build indicator shown (passing/pending depending on CI)
- No action items for the third task (no open PR yet)

```bash
# Also test list view across all projects
swift run claude-chain status --github --repo-path /Users/bill/Developer/personal/claude-chain-demo
```

Projects with open PRs show action item count badges; `hello-world` (no open PRs after completion) shows clean.

### Step 5: Verify GitHub cache was written

```bash
ls ~/Desktop/ai-dev-tools/github/gestrich-claude-chain-demo/
```

Should show numbered directories (one per open PR), each containing `gh-pr.json`, `gh-reviews.json`, `gh-checks.json`.

### Step 6: Verify `changes()` stream (cache reuse)

Run the enriched status command a second time:

```bash
swift run claude-chain status --github --repo-path /Users/bill/Developer/personal/claude-chain-demo enrichment-test
```

The second run should complete noticeably faster — PR metadata and reviews served from cache, not re-fetched from GitHub.

### Step 7: Test with ios work repo (realistic scenario)

```bash
swift run claude-chain status --github --repo-path /Users/bill/Developer/work/ios ios-26-ins-policy-AFWXBriefs-to-Diag
```

Verify PR data appears for open PRs, review states and CI status match what `chain-check.sh` shows for the same project.

### Step 8: Mac app

Ask Bill to open the Mac app, select the `claude-chain-demo` repo, switch to the Claude Chain tab, and select the `enrichment-test` project. Verify:
- Project list loads immediately (local data)
- Enrichment spinner appears briefly then disappears
- PR indicators appear in the task list for the two tasks with open PRs
- Action items banner appears if any conditions are met (e.g., no reviewers assigned)
- Sidebar badge shows action count for the project
- "Refresh GitHub" button re-fetches and updates the view
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find new features architected as afterthoughts and refactor them to integrate cleanly with the existing system, and make the necessary code changes

**Skills used**: `swift-architecture`, `ai-dev-tools-review`
**Principles applied**: The `--github` enrichment flag in `StatusCommand` was the afterthought — it duplicated `ClaudeChainModel.makeOrGetGitHubPRService` with slightly different logic (own `normalizedSlug` + `GitHubPRService` construction) rather than integrating with the existing factory. Fixed by adding `GitHubServiceFactory.createPRService(repoPath:githubAccount:dataPathsService:)` to `PRRadarCLIService` (requires adding `DataPathsService` as a direct dependency), then refactoring both `StatusCommand.makeGitHubPRService` and `ClaudeChainModel.makeOrGetGitHubPRService` to call the shared factory. Also removed the now-dead `ModelError.cannotDeriveRepoSlug` case and unused `PRRadarConfigService` import from the model.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Identify the architectural layer for every new or modified file; read the reference doc for that layer before reviewing anything else, and make the necessary code changes

**Skills used**: `swift-architecture`, `ai-dev-tools-review`
**Principles applied**: Read `layers.md`, `apps-layer.md`, `features-layer.md`, `services-layer.md`, and `sdks-layer.md` before reviewing each file. Confirmed all 13 new/modified files are in the correct layer: `ClaudeChainModel` and views in Apps, `GetChainDetailUseCase` as a Features-layer struct conforming to `UseCase`, all models/protocols/services/cache in Services. Dependency flow is strictly downward (Apps → Features → Services → SDKs). No `@Observable` outside the Apps layer. No code changes were required.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find code placed in the wrong layer entirely and move it to the correct one, and make the necessary code changes

**Skills used**: `swift-architecture`, `ai-dev-tools-review`
**Principles applied**: Read `features-layer.md`, `services-layer.md`, and `sdks-layer.md` reference docs. Reviewed all 13 new/modified files introduced in phases 1-9 against layer criteria: `GetChainDetailUseCase` (struct, `UseCase` conformance, orchestration) → Features ✓; `ChainEnrichmentModels`, `ChainModels`, `GitHubAPIServiceProtocol`, `GitHubPRCacheService`, `GitHubPRService`, `GitHubPRServiceProtocol`, `PRRadarCLIService/GitHubService`, `GitHubServiceFactory`, and shared GitHub types → Services ✓; `OctokitClient` additions (single-operation API calls, stateless struct) → SDKs ✓; `ClaudeChainModel`, views, and `StatusCommand` → Apps ✓. Dependency flow strictly downward throughout. No code changes required.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find upward dependencies (lower layers importing higher layers) and remove them, and make the necessary code changes

**Skills used**: `swift-architecture`, `ai-dev-tools-review`
**Principles applied**: Searched all Sources/ for any case of SDKs importing Services/Features, Services importing Features, or Features importing Apps — none found. Identified one undeclared transitive dependency: `GetChainDetailUseCase.swift` (ClaudeChainFeature) imports `PRRadarModelsService` without it being declared as a direct dependency of `ClaudeChainFeature` in Package.swift (worked via transitive resolution through `ClaudeChainService`). Fixed by adding `"PRRadarModelsService"` to `ClaudeChainFeature`'s dependencies list in Package.swift, making the downward Feature→Service dependency explicit.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find `@Observable` or `@MainActor` outside the Apps layer and move it up, and make the necessary code changes

**Skills used**: `swift-architecture`
**Principles applied**: Searched all changed files (Features, Services, SDKs layers) from Phases 1–7 and subsequent code review phases for `@Observable` and `@MainActor`. All occurrences were confined to the Apps layer: `ClaudeChainModel.swift` (`@MainActor @Observable` at type level, closure annotations) and `ClaudeChainView.swift` (closure `@MainActor` annotation). No `@Observable` or `@MainActor` appeared in any Features, Services, or SDKs layer file. No code changes required.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find multi-step orchestration that belongs in a use case and extract it, and make the necessary code changes

**Skills used**: `swift-architecture`, `ai-dev-tools-review`
**Principles applied**: `ClaudeChainModel.loadChainDetail` was calling two use case methods in sequence — `loadCached()` then `run()` — to implement a cache-first-then-network pattern. This multi-step orchestration belongs in the use case, not the model. Fixed by adding `stream(options:)` to `GetChainDetailUseCase` (also adding `StreamingUseCase` conformance) that yields cached data first then network data internally. Made `loadCached()` private since it's now only called by `stream()`. Simplified the model's `loadChainDetail` to a single `for try await` loop consuming the stream.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find feature-to-feature imports and replace with a shared Service or SDK abstraction, and make the necessary code changes

**Skills used**: `swift-architecture`
**Principles applied**: Audited all 9 Feature modules (ArchitecturePlannerFeature, ChatFeature, ClaudeChainFeature, CredentialFeature, EvalFeature, MarkdownPlannerFeature, PipelineFeature, PRReviewFeature, SkillBrowserFeature) via both Package.swift dependency declarations and import statements in source files. No Feature module imports another Feature module — all inter-feature shared logic is already mediated through Services (e.g., `ClaudeChainService`, `PRRadarModelsService`, `GitHubService`) and SDKs. No code changes required.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find SDK methods that accept or return app-specific or feature-specific types and replace them with generic parameters, and make the necessary code changes

**Skills used**: `swift-architecture`, `ai-dev-tools-review`
**Principles applied**: Audited all 20 SDK modules for any method accepting or returning Service/Feature/App types. Confirmed no violations: `OctokitSDK.OctokitClient` uses only OctoKit library types and SDK-local types (`CheckRun`, `CompareResult`, `ReviewCommentData`); `ClaudeChainSDK.GitHubClient` uses only `CLISDK.ExecutionResult` and primitives; all other SDKs import only other SDKs or external packages. The Service→SDK boundary is correctly maintained — `PRRadarCLIService.GitHubService` maps OctoKit types to `PRRadarModelsService` types internally, never leaking Service types into SDK signatures. No code changes required.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find SDK methods that orchestrate multiple operations and split them into single-operation methods, and make the necessary code changes

**Skills used**: `swift-architecture`
**Principles applied**: Found two violations in `OctokitClient.swift` added during the enrichment work. `requestedReviewers` was calling `pullRequest()` (another SDK method) to get the full PR then extracting reviewer logins — replaced with a direct `getJSON` call to the dedicated GitHub API endpoint (`/pulls/{number}/requested_reviewers`), adding `pullRequestRequestedReviewers` to `GitHubPath`. `getPullRequestHeadSHA` was also calling `pullRequest()` and extracting `head.sha` — removed this method entirely and moved the extraction logic into the Services-layer caller (`GitHubService.getPRHeadSHA`), which is the appropriate place for such composition.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find SDK types that hold mutable state and refactor to stateless structs, and make the necessary code changes

**Skills used**: none
**Principles applied**: Found three violations. (1) `PullRequestFile` in `OctokitClient.swift` — private decode-only struct with all `var` stored properties; changed to `let`. (2) `PersistedSession` in `AnthropicSessionStorage.swift` — encode/decode-only struct with `var lastModified`, `var summary`, `var messages`; changed to `let`. (3) `GitHubClient.mergePullRequest` and `triggerWorkflow` used `var command` + post-init mutation; refactored to `let command` with all values passed at initialization, eliminating mutation of the CLI command structs.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find error swallowing across all layers and replace with proper propagation, and make the necessary code changes

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Audited all files introduced in phases 1–7 for `try?`, empty catch blocks, and silent fallbacks. Found one harmful instance: `StatusCommand.swift`'s `--github` list mode used `try?` to silently skip projects that failed enrichment, giving users no indication of failure. Fixed to `do/catch` with an `fputs` warning to stderr. All other `try?` patterns were intentional: cache-first loading in `GetChainDetailUseCase.loadCached()` yields best-effort partial data before the authoritative network fetch; `writeCachedIndex` is explicitly non-critical; credential listing falls back to token resolution which throws its own error on missing credentials.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Verify use case types are structs conforming to `UseCase` or `StreamingUseCase`, not classes or actors, and make the necessary code changes

**Skills used**: none
**Principles applied**: Searched all Sources/ for `class` or `actor` declarations conforming to `UseCase`/`StreamingUseCase` — none found. All 70+ use case types across Features and Services layers are `struct` conforming to `UseCase` or `StreamingUseCase`. `GetChainDetailUseCase` (the primary new use case from these phases) is a `public struct` conforming to both. No code changes required.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Verify type names follow the `<Name><Layer>` convention and rename any that don't, and make the necessary code changes

**Skills used**: `swift-architecture`
**Principles applied**: Searched all files changed in phases 1–19 for `<Name><Layer>` violations. Found one: the concrete GitHub API service type `GitHubService` in `PRRadarCLIService/GitHubService.swift` had the same name as the `GitHubService` module, creating a shadowing ambiguity (local type hides the module name). Since this struct implements `GitHubAPIServiceProtocol`, the correct name is `GitHubAPIService` (matching the protocol name minus the `Protocol` suffix). Renamed the struct, renamed the file to `GitHubAPIService.swift`, and updated all references in `GitHubServiceFactory`, `GitHubAPIHistoryProvider`, `CommentService`, `PRAcquisitionService`, and `StatusCommand`.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Verify both a Mac app model and a CLI command consume each new use case, and make the necessary code changes

**Skills used**: none
**Principles applied**: Audited all use cases introduced in phases 1–7. `GetChainDetailUseCase` is the only new use case from this plan; it is consumed by both `StatusCommand.swift` (CLI, line 47) and `ClaudeChainModel.swift` (Mac app, line 128). All other use cases (`ListChainsUseCase`, `ExecuteChainUseCase`, `RunChainTaskUseCase`) are pre-existing. No code changes required.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Split files that define multiple unrelated types into one file per type, and make the necessary code changes

**Skills used**: none
**Principles applied**: Found two files with multiple unrelated types from phases 1–7. (1) `ChainEnrichmentModels.swift` mixed PR-level enrichment types (`PRReviewStatus`, `PRBuildStatus`, `EnrichedPR`) with chain project–level types (`EnrichedChainTask`, `ChainActionKind`, `ChainActionItem`, `ChainProjectDetail`) — PR enrichment types are GitHub API concepts with no chain dependency, while chain types are chain-domain aggregates; split PR types into new `PREnrichment.swift`. (2) `GitHubModels.swift` in `PRRadarModelsService` accumulated `GitHubCheckRun` (a CI check-run type) alongside PR metadata, review, comment, and repository types — CI checks are a distinct domain; extracted `GitHubCheckRun` into its own `GitHubCheckRun.swift`.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Move supporting enums and nested types below their primary type, not above it, and make the necessary code changes

**Skills used**: none
**Principles applied**: Found three violations in files from the enrichment phases. (1) `PREnrichment.swift` — `PRReviewStatus` and `PRBuildStatus` were defined above `EnrichedPR`, the primary type that uses them; moved both below `EnrichedPR`. (2) `ChainEnrichmentModels.swift` — `ChainActionKind` was defined above `ChainActionItem`, which uses it as a property type; moved `ChainActionKind` below `ChainActionItem`. (3) `PRRadarModelsService/GitHubModels.swift` — `GitHubReviewState` was added (Phase 1) above `GitHubReview`; moved it below `GitHubReview`.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find fallback values that hide failures and suppressed errors — remove or replace both with proper propagation, and make the necessary code changes

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Found two clear violations from phases 1–7. (1) `StatusCommand.makeGitHubPRService` used `(try? CredentialSettingsService().listCredentialAccounts()) ?? []` — if credential listing fails, the error is silently swallowed and the command proceeds with an empty accounts list, eventually falling back to a "default" account name; changed to `try` so any credential system failure propagates immediately. (2) `GitHubPRService.checkRuns` used `guard let headSHA = pr.headRefOid else { return [] }` — a PR with no head commit SHA returns empty check runs indistinguishable from "CI not configured"; added `GitHubPRServiceError.missingHeadRefOid(prNumber:)` to the `GitHubService` module and changed the guard to throw it. The `try?` patterns in `GetChainDetailUseCase.loadCached` were left unchanged (blessed by the prior error-swallowing review phase as intentional best-effort cache before network). The `try? writeCachedIndex` was also left unchanged (explicitly non-critical cache write).
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Remove backwards compatibility shims added before release — there is no backwards compatibility obligation for unreleased code, and make the necessary code changes

**Skills used**: none
**Principles applied**: Found one backwards compat shim: `GitHubReview.state` was `String?` (the pre-existing PRRadar type), kept as-is in Phase 1 to avoid updating callers, even though `GitHubReviewState` enum was added alongside it. Changed `state` to `GitHubReviewState?` in the struct definition, updated the two `GitHubAPIService.swift` mapping sites to use `GitHubReviewState(rawValue: review.state.rawValue)`, and simplified `GetChainDetailUseCase.buildReviewStatus` to use direct enum comparisons (`.approved`, `.pending`) instead of `.rawValue` string comparisons.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Replace `String`, `[String: Any]`, and raw dictionary types in APIs with proper typed models, and make the necessary code changes

**Skills used**: none
**Principles applied**: Found one violation in the new phase 1–7 code: `GitHubCheckRun` used `status: String` and `conclusion: String?` with hardcoded string comparisons (`== "success"`, `== "failure"`, `!= "completed"`). Added `GitHubCheckRunStatus` and `GitHubCheckRunConclusion` enums (String raw values, `Codable`, `Sendable`) to `GitHubCheckRun.swift`. Updated `GitHubCheckRun` init and computed properties to use the enums. Updated `GitHubAPIService.checkRuns` to map `OctokitSDK.CheckRun` (SDK-layer raw strings) to typed enums at the service boundary. Updated `GetChainDetailUseCase.buildBuildStatus` to use `.completed` instead of `"completed"`. The `OctokitClient.CheckRun` struct in the SDKs layer was left unchanged — SDK types wrap raw JSON and the mapping to typed models is the service's responsibility.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Replace optional types with non-optional where the value must be present, and make the necessary code changes
**Skills used**: `ai-dev-tools-debug`
**Principles applied**: Changed `GitHubReview.state: GitHubReviewState?` to `GitHubReviewState`. The GitHub API always returns a review state and OctoKit's `Review.state` is already non-optional, so the optional was never meaningful. Added an exhaustive `Review.State.toGitHubReviewState` mapping extension in `OctokitMapping.swift` to replace the failable `rawValue`-based conversion in both `GitHubAPIService` call sites.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Remove AI-changelog-style comments and replace with concise documentation or remove entirely, and make the necessary code changes

**Skills used**: none
**Principles applied**: Found AI-changelog-style comments with bold `**Problem**`/`**Current Usage**`/`**Future**` etc. headers in two files from the enrichment phases. In `OctokitClient.swift`, replaced the 27-line block comment (with `**Problem**`, `**OctoKit Bug**`, `**Why We Can't Fix This Properly**`, `**This Workaround**`, `**Tested With**`, `**Future**` sections) with a 4-line concise comment; also simplified the `listPullRequestFiles` doc comment that referenced the now-removed block. In `GitHubOperations.swift` (modified in Phase 10), stripped verbose doc comment sections from four static methods: `listPullRequests`, `listMergedPullRequests`, `listOpenPullRequests`, `listPullRequestsForProject`, and `getCurrentRepository` — each had `**Current Usage**`, `**Design Principles**`, `**Usage Examples**`, `Example:`, and `See Also:` blocks that documented history and speculative usage rather than behavior.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find duplicated logic and consolidate into a single shared implementation, and make the necessary code changes

**Skills used**: none
**Principles applied**: Found three duplications in phases 1–7 code. (1) `StatusCommand` had identical project-not-found lookup blocks in both the `--github` and non-`--github` paths — extracted into `findProject(named:in:)`. (2) `StatusCommand` had the same project summary footer calculation (`totalCompleted`/`totalAll` + print) in both `printEnrichedProjectList` and `printProjectList` — extracted into `printProjectSummaryFooter(_:)`. (3) `GitHubPRCacheService` had the same decode-from-file pattern repeated across all five read functions and the same encode-to-file-then-yield pattern across four PR-level write functions — extracted into private `readFile<T>(at:)` and `writePRFile<T>(_:to:prNumber:)` generics. (4) `GetChainDetailUseCase` had the same four-line `enrichedPRsByHash` insertion (guard `headRefName` → `BranchInfo` → assign) repeated three times — extracted into `register(_:into:)`.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Replace force unwraps with proper optional handling, and make the necessary code changes

**Skills used**: none
**Principles applied**: Found three force unwraps in `OctokitClient.swift` (introduced in Phase 1). (1) `toOctokitFile()` used `try!` for `JSONSerialization.data` and `decoder.decode` — changed the method to `throws -> PullRequest.File` and propagated errors to the caller with `try`. (2) `makeRequest` used `URLComponents(string:)!` and `components.url!` — replaced with `guard let` + `preconditionFailure` to surface a descriptive message on programming errors rather than a silent crash. No force unwraps were found in any other spec-related files (GetChainDetailUseCase, PREnrichment, ChainEnrichmentModels, GitHubCheckRun, GitHubModels, GitHubPRService, GitHubAPIService, OctokitMapping, ClaudeChainModel, StatusCommand).
