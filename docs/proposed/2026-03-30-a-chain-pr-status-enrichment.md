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

## - [ ] Phase 5: Update `ClaudeChainModel` and Mac UI detail view

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

## - [ ] Phase 6: Update CLI `status` command

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

## - [ ] Phase 7: Validation

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
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find new features architected as afterthoughts and refactor them to integrate cleanly with the existing system, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Identify the architectural layer for every new or modified file; read the reference doc for that layer before reviewing anything else, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find code placed in the wrong layer entirely and move it to the correct one, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find upward dependencies (lower layers importing higher layers) and remove them, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find `@Observable` or `@MainActor` outside the Apps layer and move it up, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find multi-step orchestration that belongs in a use case and extract it, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find feature-to-feature imports and replace with a shared Service or SDK abstraction, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find SDK methods that accept or return app-specific or feature-specific types and replace them with generic parameters, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find SDK methods that orchestrate multiple operations and split them into single-operation methods, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find SDK types that hold mutable state and refactor to stateless structs, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find error swallowing across all layers and replace with proper propagation, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Verify use case types are structs conforming to `UseCase` or `StreamingUseCase`, not classes or actors, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Verify type names follow the `<Name><Layer>` convention and rename any that don't, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Verify both a Mac app model and a CLI command consume each new use case, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Split files that define multiple unrelated types into one file per type, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Move supporting enums and nested types below their primary type, not above it, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find fallback values that hide failures and suppressed errors — remove or replace both with proper propagation, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Remove backwards compatibility shims added before release — there is no backwards compatibility obligation for unreleased code, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Replace `String`, `[String: Any]`, and raw dictionary types in APIs with proper typed models, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Replace optional types with non-optional where the value must be present, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Remove AI-changelog-style comments and replace with concise documentation or remove entirely, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find duplicated logic and consolidate into a single shared implementation, and make the necessary code changes
## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Replace force unwraps with proper optional handling, and make the necessary code changes
