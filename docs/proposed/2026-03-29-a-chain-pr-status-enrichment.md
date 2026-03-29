## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture (Apps, Features, Services, SDKs) with dependency rules and use case patterns |
| `ai-dev-tools-debug` | CLI commands, project paths, and debugging for AIDevTools |

## Background

The claude-chain skill (`~/.claude/skills/claude-chain/`) provides rich chain status information via shell scripts that call the GitHub API — PR review status, build/CI state, draft detection, days open, and actionable indicators (e.g., "this draft PR needs to be moved to review"). None of this GitHub-enriched data is available in the Mac app or CLI today.

Currently, `ListChainsUseCase` reads only the local `spec.md` files and returns `ChainProject` / `ChainTask` — purely local data with no GitHub awareness. The `StatisticsService` fetches GitHub data but is designed for aggregate reports, not per-chain detail views.

The goal is to bring the same richness as the skill's `chain-check.sh` and `chain-status.sh` into the app, so both the CLI `status` command and the Mac UI detail view show:

- Which tasks have open PRs (with PR number, URL, age)
- PR review state: approved reviewers, pending reviewers
- PR build/CI status: passing, failing, pending (with check names)
- Draft vs ready-for-review indication
- Merge conflict detection
- Actionable indicators (e.g., draft PRs needing promotion, stale PRs, failing CI)

**Key constraint**: GitHub API calls are expensive/slow. We fetch enriched data on-demand when a chain is opened (detail view), not during list loading. The list view continues to use fast local-only data. The fetch happens through model -> use case, and the view updates reactively when data arrives.

**GitHub client**: Use [OctoKit](https://github.com/nerdishbynature/octokit.swift) (`nerdishbynature/octokit.swift`, from version `0.11.0`) as the Swift GitHub API client. Add it as a dependency in `Package.swift`. OctoKit provides type-safe access to PRs (`pullRequests()`, `pullRequest()`), reviews (`listReviews()` with `Review.State.approved`), requested reviewers (`readPullRequestRequestedReviewers()`), draft status, and commit statuses. For features OctoKit doesn't cover (check runs/suites via the modern Checks API, and mergeable state), fall back to `gh` CLI calls.

**Repo context**: The chain scripts are hardcoded to `jeppesen-foreflight/ff-ios`. The app needs to work generically — the repo identifier should come from the chain project's configuration or be derived from the repository's git remote.

## Phases

## - [ ] Phase 1: Add GitHub PR enrichment models to ClaudeChainService

**Skills to read**: `swift-architecture`

Add new domain models that represent the enriched GitHub state for a chain's PRs. These go in ClaudeChainService since they extend the existing `GitHubPullRequest` ecosystem.

New models in `GitHubModels.swift`:

- **`PRReviewStatus`** — struct with `approvedBy: [String]`, `pendingReviewers: [String]`
- **`PRBuildStatus`** — enum: `.passing`, `.failing(checks: [String])`, `.pending(checks: [String])`, `.conflicting`
- **`EnrichedPR`** — struct combining: `pr: GitHubPullRequest`, `isDraft: Bool`, `reviewStatus: PRReviewStatus`, `buildStatus: PRBuildStatus`

Add to `GitHubPullRequest`:
- `isDraft: Bool` field (add to `fromDict` parsing, add to `listPullRequests` `--json` fields)

New model for the enriched chain view (in `ClaudeChainFeature` alongside `ChainProject`):

- **`ChainProjectDetail`** — struct with:
  - `project: ChainProject` (the existing local data)
  - `enrichedTasks: [EnrichedChainTask]` — tasks with optional PR linkage
  - `actionItems: [ChainActionItem]` — things needing attention

- **`EnrichedChainTask`** — struct with:
  - `task: ChainTask`
  - `enrichedPR: EnrichedPR?` — linked PR with review/build data

- **`ChainActionItem`** — struct with:
  - `kind: ChainActionKind` — enum: `.draftNeedsReview`, `.ciFailure`, `.mergeConflict`, `.stalePR`, `.needsReviewers`
  - `prNumber: Int`
  - `message: String`

## - [ ] Phase 2: Add GitHub enrichment to ClaudeChainSDK

**Skills to read**: `swift-architecture`

Add OctoKit (`nerdishbynature/octokit.swift`) as a dependency in `Package.swift` and create a new SDK-level wrapper that uses it for GitHub API calls.

Create a new `OctoKitClient` in ClaudeChainSDK that wraps OctoKit's `Octokit` class, configured with `TokenConfiguration`. This provides type-safe access to:

- **`pullRequest(owner:repository:number:)`** — fetches a single PR with draft status
- **`listReviews(owner:repository:pullRequestNumber:)`** — gets review states (approved, changes requested, etc.)
- **`readPullRequestRequestedReviewers(owner:repository:pullRequestNumber:)`** — gets pending reviewers
- **`listCommitStatuses(owner:repository:ref:)`** — gets legacy commit statuses

For features OctoKit doesn't cover, keep `gh` CLI fallbacks in `GitHubOperations`:

- **`getPullRequestChecks(repo:prNumber:)`** — runs `gh pr checks <number>` and returns parsed output (check name, status, conclusion) for the modern Checks API
- **`getPullRequestMergeable(repo:prNumber:)`** — runs `gh pr view <number> --json mergeable` for merge conflict detection

The feature layer will orchestrate calling both OctoKit and `gh` CLI methods per-PR.

## - [ ] Phase 3: Create `GetChainDetailUseCase` in ClaudeChainFeature

**Skills to read**: `swift-architecture`

Create a new use case that orchestrates fetching enriched chain data. This is the single entry point both CLI and Mac app will call.

**`GetChainDetailUseCase`**:
- **Input**: `Options(repoPath: URL, projectName: String, repo: String)`
- **Output**: `ChainProjectDetail`
- **Flow**:
  1. Call `ListChainsUseCase` to get local `ChainProject` for the specified project
  2. Use `PRService.getOpenPrsForProject()` to find open PRs for this project
  3. For each open PR, fetch enriched data (review status, build status, draft state) via the new SDK methods — use `TaskGroup` for concurrent fetching
  4. Match PRs to tasks using the existing `taskHash` mechanism (branch name → task hash → spec task)
  5. Build `EnrichedChainTask` array by merging local tasks with their matched PRs
  6. Generate `actionItems` by scanning enriched PRs for: draft PRs, failing CI, merge conflicts, stale PRs, PRs with no reviewers assigned
  7. Return `ChainProjectDetail`

The repo string (e.g., `jeppesen-foreflight/ff-ios`) needs to be derived. Options:
- Read from `configuration.yml` if a `repo` field is present
- Fall back to parsing the git remote of the repository at `repoPath`
- Accept as explicit parameter from caller

For now, add a `repo` field to `ProjectConfiguration` and fall back to git remote parsing.

## - [ ] Phase 4: Update `ClaudeChainModel` and Mac UI detail view

**Skills to read**: `swift-architecture`

Update the Mac app to fetch and display enriched data when a chain project is selected.

**Model changes** (`ClaudeChainModel`):
- Add `chainDetail: ChainProjectDetail?` state property
- Add `loadChainDetail(projectName:repoPath:repo:)` method that calls `GetChainDetailUseCase`
- Detail loading is triggered when a project is selected (not during list loading)
- While loading, show the existing local data immediately, then overlay enriched data when it arrives

**View changes** (`ClaudeChainView.swift`):

In `ChainProjectDetailView`:
- Show an action items banner at the top when `actionItems` is non-empty (colored badges like "2 draft PRs need review", "1 CI failure")
- In the task list, for tasks with a linked PR show:
  - PR number as a clickable link (opens in browser)
  - Age badge (e.g., "3d")
  - Review state indicator: green checkmark for approved, yellow dot for pending review, gray for no reviewers
  - Build indicator: green checkmark for passing, red X for failing, yellow spinner for pending, red conflict icon for merge conflicts
  - Draft badge if PR is in draft state

In `ChainProjectRow` (sidebar):
- Add a small badge/indicator if the project has action items (e.g., red dot or count badge) — only visible after detail has been loaded for that project

## - [ ] Phase 5: Update CLI `status` command

**Skills to read**: `swift-architecture`

Update `StatusCommand` to support an `--enriched` flag (or `--github` / `-g`) that fetches GitHub data using `GetChainDetailUseCase`.

Without the flag, behavior stays as-is (fast, local-only). With the flag:

- **Detail view** (single project): Show enriched task list with PR info columns:
  ```
  ✓ `task description`
  ○ `task description`  PR #19345 (3d) ✅ Build  👤 bill_jepp approved
  ○ `task description`  PR #19350 (1d) ❌ Build  ⏳ Pending review: nati_jepp
  ○ `task description`  [DRAFT] PR #19360 (0d) ⚠️ Needs review promotion
  ```

- **List view** (all projects): Show the same progress bars plus a count of action items:
  ```
  project-name  [████░░░░]  5/10 completed  ⚠ 2 actions needed
  ```

- After the task list, show an "Action Items" section listing all items that need attention.

The `--repo` option provides the GitHub repository identifier. If omitted, attempt to derive from git remote.

## - [ ] Phase 6: Validation

**Skills to read**: `swift-architecture`

- Build both `claude-chain` CLI and `AIDevToolsKitMac` targets and verify clean compilation
- Test CLI: `swift run claude-chain status --repo-path /Users/bill/Developer/work/ios ios-26-ins-policy-AFWXBriefs-to-Diag` (local-only, should still work)
- Test CLI enriched: `swift run claude-chain status --repo-path /Users/bill/Developer/work/ios --github ios-26-ins-policy-AFWXBriefs-to-Diag` — verify PR data appears for open PRs
- Verify the enriched output matches what `chain-check.sh` shows for the same project (cross-reference PR numbers, review states, build statuses)
- Test with a project that has no open PRs (e.g., `remove-file-spaces` which is 47/47 complete) — should show clean output with no PR data
- Test list view with `--github` flag across all projects
- Verify Mac app builds and the detail view loads enriched data when selecting a project (ask Bill to run the app and check)
