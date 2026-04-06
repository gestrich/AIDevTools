## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | Checks and fixes Swift code for 4-layer architecture violations (layer placement, dependencies, orchestration) |
| `ai-dev-tools-enforce` | Orchestrates enforcement of coding standards — run after every phase |
| `ai-dev-tools-swift-testing` | Swift Testing conventions for writing/reviewing test files |
| `swift-architecture` | 4-layer Swift app architecture guide (Apps, Features, Services, SDKs) |

## Background

The claude chain/sweep feature currently calls the `gh` CLI binary for all GitHub write operations: PR creation, merging, closing, label management, workflow dispatch, and branch deletion. The project already has a `GitHubService` layer wrapping `OctokitClient` with protocol-based design and caching — but it is read-only. The goal is to extend `GitHubService` with write operations (and TTL-cached reads for new list ops) so chain/sweep can drop the `gh` dependency entirely.

The existing service stack (read-only today):
```
GitHubPRServiceProtocol  (GitHubService)     ← chain/sweep target interface
  └─ GitHubPRService     (GitHubService, cached)
       └─ GitHubAPIServiceProtocol  (GitHubService)
            └─ GitHubAPIService     (PRRadarCLIService)
                 └─ OctokitClient   (OctokitSDK, direct REST)
```

**Package dep gaps to close:**
- `PipelineService` — needs `GitHubService` added
- `ClaudeChainService` — needs `GitHubService` added
- `ClaudeChainFeature` — already has `GitHubService` ✅

**`gh` calls being replaced (by file):**
- `PRStep.swift` — `gh pr create`, `gh pr view`, `gh pr list`
- `CreatePRStepHandler.swift` — `gh pr create`, `gh pr view`, `gh pr comment`
- `ChainPRCommentStep.swift` — `gh pr comment`
- `GitHubOperations.swift` — `gh pr comment`, `gh api` (branch delete), `gh api` (file content)
- `FinalizeStagedTaskUseCase.swift` — `gh pr create`, `gh pr view`, `gh pr comment`
- `RunSpecChainTaskUseCase.swift` — `gh pr comment`
- `WorkflowService.swift` — `gh workflow run`
- `FinalizeCommand.swift` — `gh pr create`, `gh pr view`

---

## - [x] Phase 1: Extend `OctokitClient` with Write/Mutation Methods

**Skills used**: `swift-architecture`, `ai-dev-tools-architecture`
**Principles applied**: All new methods follow the existing `makeMutationRequest` / `URLSession.shared.data(for:)` / `switch httpResponse.statusCode` pattern. New `GitHubPath` entries added alphabetically. `CreatedPullRequest` and `WorkflowRun` added as `public Sendable` structs (SDK layer convention). `fromEnvironment()` reads `GH_TOKEN` then `GITHUB_TOKEN`. `deleteResource` tolerates 204/404 for idempotent branch deletion. `createLabel` silently succeeds on 422 (already exists).

**Skills to read**: `swift-architecture`, `ai-dev-tools-architecture`

**File:** `AIDevToolsKit/Sources/SDKs/OctokitSDK/OctokitClient.swift`

All new methods follow the existing `makeMutationRequest` / `URLSession.shared.data(for:)` / `switch httpResponse.statusCode` pattern already established in this file.

Add to `GitHubPath` (alphabetical order):
- `branchRef(_:_:branch:)` → `repos/{}/{}/git/refs/heads/{branch}`
- `branches(_:_:)` → `repos/{}/{}/branches`
- `issueAssignees(_:_:number:)` → `repos/{}/{}/issues/{}/assignees`
- `issueLabels(_:_:number:)` → `repos/{}/{}/issues/{}/labels`
- `labels(_:_:)` → `repos/{}/{}/labels`
- `pullRequestMerge(_:_:number:)` → `repos/{}/{}/pulls/{}/merge`
- `pullRequestReviewers(_:_:number:)` → `repos/{}/{}/pulls/{}/requested_reviewers`
- `workflowDispatch(_:_:workflowId:)` → `repos/{}/{}/actions/workflows/{}/dispatches`
- `workflowRuns(_:_:)` → `repos/{}/{}/actions/runs`

Add new public result types:
```swift
public struct CreatedPullRequest: Sendable { public let number: Int; public let htmlURL: String }
public struct WorkflowRun: Sendable { public let id: Int; public let status: String; public let conclusion: String?; public let headBranch: String?; public let htmlURL: String? }
```

Add static factory:
```swift
public static func fromEnvironment() -> OctokitClient?  // reads GH_TOKEN then GITHUB_TOKEN
```

Add private helper:
- `deleteResource(path: String) async throws` — DELETE, tolerates 204/404

Add public utility:
- `parseRepoSlug(_ slug: String) -> (owner: String, repository: String)?` — splits `"owner/repo"` on `/`

New public async methods:

| Method | HTTP | Key status codes |
|--------|------|-----------------|
| `createPullRequest(owner:repository:title:body:head:base:draft:)` | POST `/pulls` | 201→`CreatedPullRequest`; 422→throw containing "already_exists" |
| `updatePullRequestState(owner:repository:number:state:)` | PATCH `/pulls/{}` | 200→ok |
| `mergePullRequest(owner:repository:number:mergeMethod:)` | PUT `/pulls/{}/merge` | 200→ok; 405→throw |
| `addAssignees(owner:repository:issueNumber:assignees:)` | POST `/issues/{}/assignees` | 201→ok |
| `addLabels(owner:repository:issueNumber:labels:)` | POST `/issues/{}/labels` | 200→ok |
| `createLabel(owner:repository:name:color:description:)` | POST `/labels` | 201→ok; 422→silently ok |
| `requestReviewers(owner:repository:number:reviewers:)` | POST `/pulls/{}/requested_reviewers` | 201→ok |
| `deleteBranchRef(owner:repository:branch:)` | DELETE via `deleteResource` | 204/404→ok |
| `listBranches(owner:repository:)` | GET `/branches?per_page=100` | 200→`[String]` names |
| `triggerWorkflowDispatch(owner:repository:workflowId:ref:inputs:)` | POST `/actions/workflows/{}/dispatches` | 204→ok |
| `listWorkflowRuns(owner:repository:workflow:branch:limit:)` | GET `/actions/runs` | 200→`[WorkflowRun]` |
| `pullRequestByHeadBranch(owner:repository:branch:)` | GET `/pulls?head={owner}:{branch}` | 200→`CreatedPullRequest?` first open match |

## - [x] Phase 2: Enforce on Phase 1

**Skills used**: `ai-dev-tools-enforce`, `ai-dev-tools-architecture`, `ai-dev-tools-build-quality`, `ai-dev-tools-code-organization`, `ai-dev-tools-code-quality`, `ai-dev-tools-swift-testing`
**Principles applied**: Removed duplicate `GitHubPath.pullRequestReviewers` (identical path to pre-existing `pullRequestRequestedReviewers`); updated `requestReviewers` mutation to use the canonical path function. Build confirmed clean. No other violations in the Phase 1 additions — new public types are correctly `Sendable` structs with `let` properties, all write methods follow the existing single-operation SDK pattern, and `fromEnvironment()` correctly reads env vars at the SDK layer.

Run `ai-dev-tools-enforce` on all files changed in Phase 1.

---

## - [x] Phase 3: Add Write Methods to `GitHubAPIServiceProtocol` and `GitHubAPIService`

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: All 12 new methods added alphabetically to the protocol; each `GitHubAPIService` implementation is a thin one-liner forward to the corresponding `OctokitClient` method using stored `owner`/`repo`. No caching at this layer. `closePullRequest` maps to `updatePullRequestState(state: "closed")` per the SDK design.

**Skills to read**: `ai-dev-tools-architecture`

**Files:**
- `AIDevToolsKit/Sources/Services/GitHubService/GitHubAPIServiceProtocol.swift`
- `AIDevToolsKit/Sources/Services/PRRadarCLIService/GitHubAPIService.swift`

Add to `GitHubAPIServiceProtocol` (keep alphabetical):
```swift
func addAssignees(prNumber: Int, assignees: [String]) async throws
func addLabels(prNumber: Int, labels: [String]) async throws
func closePullRequest(number: Int) async throws
func createLabel(name: String, color: String, description: String) async throws
func createPullRequest(title: String, body: String, head: String, base: String, draft: Bool) async throws -> CreatedPullRequest
func deleteBranch(branch: String) async throws
func listBranches() async throws -> [String]
func listWorkflowRuns(workflow: String, branch: String?, limit: Int) async throws -> [WorkflowRun]
func mergePullRequest(number: Int, mergeMethod: String) async throws
func pullRequestByHeadBranch(branch: String) async throws -> CreatedPullRequest?
func requestReviewers(prNumber: Int, reviewers: [String]) async throws
func triggerWorkflowDispatch(workflowId: String, ref: String, inputs: [String: String]) async throws
```

Implement each in `GitHubAPIService` as a thin forward to the corresponding new `OctokitClient` method (using stored `owner`/`repo`). No caching at this layer.

## - [x] Phase 4: Enforce on Phase 3

**Skills used**: `ai-dev-tools-enforce`, `ai-dev-tools-architecture`, `ai-dev-tools-build-quality`, `ai-dev-tools-code-organization`, `ai-dev-tools-code-quality`, `ai-dev-tools-swift-testing`
**Principles applied**: No violations found in Phase 3 additions. New protocol methods are alphabetically ordered and correctly typed; `GitHubAPIService` write method implementations are thin forwards with no orchestration, no error swallowing, no force unwraps, and no AI-changelog comments. Build confirmed clean.

Run `ai-dev-tools-enforce` on all files changed in Phase 3.

---

## - [x] Phase 5: Add Write + Cached-Read Methods to `GitHubPRServiceProtocol` and `GitHubPRService`

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: All mutation methods forward to `apiClient` with no caching; `createPullRequest` orchestrates create → addLabels → addAssignees → requestReviewers then invalidates the PR list cache via `updateAllPRs`. `listBranches(ttl:)` and `listWorkflowRuns(ttl:)` follow the TTL-cache pattern from `branchHead` and `listDirectoryNames`. `WorkflowRun` and `CreatedPullRequest` gained `Codable` conformance in `OctokitSDK` to enable JSON caching. `postIssueComment` added to `GitHubAPIServiceProtocol` to expose the existing `GitHubAPIService` implementation through the protocol. Convenience factory `make(token:owner:repo:)` added to `GitHubServiceFactory` in `PRRadarCLIService` (rather than directly on `GitHubPRService`) to avoid creating a circular dependency (`GitHubService` → `PRRadarCLIService` → `GitHubService`).

**Skills to read**: `ai-dev-tools-architecture`

**Files:**
- `AIDevToolsKit/Sources/Services/GitHubService/GitHubPRServiceProtocol.swift`
- `AIDevToolsKit/Sources/Services/GitHubService/GitHubPRService.swift`

Add to `GitHubPRServiceProtocol` (keep alphabetical):
```swift
// Mutations — no caching; forward to apiService
func closePullRequest(number: Int) async throws
func createLabel(name: String, color: String, description: String) async throws
func createPullRequest(title: String, body: String, head: String, base: String, draft: Bool,
                       labels: [String], assignees: [String], reviewers: [String]) async throws -> CreatedPullRequest
func deleteBranch(branch: String) async throws
func mergePullRequest(number: Int, mergeMethod: String) async throws
func postIssueComment(prNumber: Int, body: String) async throws
func pullRequestByHeadBranch(branch: String) async throws -> CreatedPullRequest?
func triggerWorkflowDispatch(workflowId: String, ref: String, inputs: [String: String]) async throws

// Cached reads — new
func listBranches(ttl: TimeInterval) async throws -> [String]
func listWorkflowRuns(workflow: String, branch: String?, limit: Int, ttl: TimeInterval) async throws -> [WorkflowRun]
```

`GitHubPRService` implementations:
- **Mutations**: forward to `apiService.*`. `createPullRequest` orchestrates: create → `addLabels` → `addAssignees` → `requestReviewers`. After create/merge/close, call `updateAllPRs` to invalidate the cached PR list.
- **`listBranches(ttl:)`**: TTL-based cache in `GitHubPRCacheService`, matching the `branchHead(branch:ttl:)` pattern.
- **`listWorkflowRuns(...ttl:)`**: TTL-based cache (default 60 s).

Also add a convenience static factory if not already present:
```swift
public static func make(token: String, owner: String, repo: String) -> GitHubPRService
// builds OctokitClient → GitHubAPIService → GitHubPRService
```

## - [x] Phase 6: Enforce on Phase 5

**Skills used**: `ai-dev-tools-enforce`, `ai-dev-tools-code-quality`
**Principles applied**: Extracted duplicated `sanitise` closure in `GitHubPRCacheService` (introduced by Phase 5's `workflowRunsURL`) into a shared private method used by `branchHeadURL`, `directoryURL`, and `workflowRunsURL`. Replaced `?? temporaryDirectory` fallback in `GitHubServiceFactory.make` with a `guard`/`preconditionFailure` since app support directory unavailability is a genuine programming error, not a recoverable condition. Build confirmed clean.

Run `ai-dev-tools-enforce` on all files changed in Phase 5.

---

## - [x] Phase 7: Update `Package.swift` + Migrate `PRStep`, `CreatePRStepHandler`, `ChainPRCommentStep`

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Added `GitHubService`, `OctokitSDK`, `PRRadarCLIService`, `PRRadarModelsService` to `PipelineService` deps; added `GitHubService`, `PRRadarCLIService` to `ClaudeChainService` deps. `PRRadarCLIService` needed (beyond the spec's `GitHubService`-only mention) because `GitHubServiceFactory.make` — which Phase 5 placed there to avoid a circular dep — is required to construct `GitHubPRService` lazily in the default case. `OctokitSDK` needed for explicit `CreatedPullRequest` type annotation. All three types now store `githubService: (any GitHubPRServiceProtocol)?` with nil default; when nil, the service is built lazily in `run()`/`execute()` using env token + detected repo slug, keeping existing callers unmodified. Temp body files eliminated — body strings passed directly. `PRListItem`/`PRNumberItem` private structs removed; PR number and URL now come from `CreatedPullRequest` returned by `createPullRequest` or recovered via `pullRequestByHeadBranch`. `postIssueComment(prNumber:body:)` replaces `gh pr comment` in `ChainPRCommentStep`. Build confirmed clean.

**Skills to read**: `ai-dev-tools-architecture`

**Files:**
- `AIDevToolsKit/Package.swift`
- `AIDevToolsKit/Sources/Services/PipelineService/PRStep.swift`
- `AIDevToolsKit/Sources/Services/PipelineService/handlers/CreatePRStepHandler.swift`
- `ChainPRCommentStep.swift` (locate; may be in `PipelineService` or `ClaudeChainFeature`)

**`Package.swift`:** Add `"GitHubService"` to `PipelineService` and `ClaudeChainService` target dependencies.

**`PRStep.swift`:**
- Remove `private let cliClient: CLIClient`
- Add `private let githubService: any GitHubPRServiceProtocol`
- Default init: use `GitHubPRService.make(token:owner:repo:)` reading token from env and repo from `detectRepoSlug`
- Replace `gh pr list` (count open PRs) → `githubService.listPullRequests(limit:filter:).count`
- Replace `gh pr create` → `githubService.createPullRequest(title:body:head:base:draft:labels:assignees:reviewers:)`
- On "already_exists" error → `githubService.pullRequestByHeadBranch(branch:)` for URL recovery
- Replace `gh pr view {branch} --json number` → `githubService.pullRequestByHeadBranch(branch:)?.number`
- No temp body file — pass body string directly
- Remove `CLIClient` import

**`CreatePRStepHandler.swift`:**
- Same pattern: inject `any GitHubPRServiceProtocol`; replace all three `gh` calls with service methods

**`ChainPRCommentStep.swift`:**
- Replace `CLIClient.execute("gh", ["pr", "comment", ...])` → `githubService.postIssueComment(prNumber:body:)`
- No temp file needed

## - [x] Phase 8: Enforce on Phase 7

**Skills used**: `ai-dev-tools-enforce`, `ai-dev-tools-code-organization`
**Principles applied**: Moved `TextAccumulator` (supporting type) below the primary type `CreatePRStepHandler` in `CreatePRStepHandler.swift` — supporting types must appear after the primary type. No architectural violations, force unwraps, or AI-changelog comments in Phase 7 additions. Build confirmed clean.

Run `ai-dev-tools-enforce` on all files changed in Phase 7.

---

## - [ ] Phase 9: Migrate `GitHubOperations` + Chain Feature Callers

**Skills to read**: `ai-dev-tools-architecture`

**Files:**
- `AIDevToolsKit/Sources/Services/ClaudeChainService/GitHubOperations.swift`
- `AIDevToolsKit/Sources/Features/ClaudeChainFeature/usecases/FinalizeStagedTaskUseCase.swift`
- `AIDevToolsKit/Sources/Features/ClaudeChainFeature/usecases/RunSpecChainTaskUseCase.swift`
- `AIDevToolsKit/Sources/Features/ClaudeChainFeature/WorkflowService.swift`
- `AIDevToolsKit/Apps/ClaudeChainCLI/FinalizeCommand.swift`

**`GitHubOperations.swift`:** Change init to accept `any GitHubPRServiceProtocol` instead of `GitHubClient`. Replace instance methods:
- `postPRCommentAsync` → `githubService.postIssueComment(prNumber:body:)`
- `deleteBranchAsync` → `githubService.deleteBranch(branch:)`
- `getFileFromBranch` (instance) → `githubService.fileContent(path:ref:)`
- Mark `ghApiCall` instance method `@available(*, deprecated)`
- Mark all static `runGhCommand`-based static methods `@available(*, deprecated)`

**`FinalizeStagedTaskUseCase.swift`:** Build `GitHubPRService.make(...)` from env token + repoSlug. Replace:
- `runGhCommand(["pr", "create", ...])` → `githubService.createPullRequest(...)`
- `runGhCommand(["pr", "view", ..., ".url"])` → `githubService.pullRequestByHeadBranch(...)?.htmlURL`
- `runGhCommand(["pr", "view", ..., "number"])` → `githubService.pullRequestByHeadBranch(...)?.number`
- `runGhCommand(["pr", "comment", ...])` → `githubService.postIssueComment(...)` (no temp file)

**`RunSpecChainTaskUseCase.swift`:** Replace `runGhCommand(["pr", "comment", ...])` → `githubService.postIssueComment(...)`.

**`WorkflowService.swift`:** Inject `any GitHubPRServiceProtocol`. Replace `runGhCommand(["workflow", "run", ...])` → `githubService.triggerWorkflowDispatch(workflowId:ref:inputs:)`.

**`FinalizeCommand.swift`:** Build `GitHubPRService.make(token: ghToken, ...)`. Replace `runGhCommand` PR create/view calls with service methods.

## - [ ] Phase 10: Enforce on Phase 9

**Skills to read**: `ai-dev-tools-enforce`

Run `ai-dev-tools-enforce` on all files changed in Phase 9.

---

## - [ ] Phase 11: Delete Dead `gh`-Backed Code + Validation

**Skills to read**: `ai-dev-tools-build-quality`, `ai-dev-tools-enforce`, `ai-dev-tools-swift-testing`

**Delete / remove:**
- `static func runGhCommand(args:)` from `GitHubOperations`
- `static func ghApiCall(...)` from `GitHubOperations`
- `private let githubClient: GitHubClient` and `GitHubClient`-based init from `GitHubOperations`
- `CLIClient` imports from `GitHubOperations.swift`
- Verify no remaining callers of `GitHubClient`; if none, delete `GitHubClient.swift` and `GitHubCLI.swift` from `ClaudeChainSDK`
- Remove `ClaudeChainSDK` from `ClaudeChainService` target deps in `Package.swift` if only `GitHubClient`/`GitHubCLI` were used (verify first with grep)

**Validation:**
- `swift build` in `AIDevToolsKit/` — zero compiler errors/warnings
- `swift test` — all existing tests pass
- `grep -r '"gh"' AIDevToolsKit/Sources` — zero matches
- Manually trigger a chain sweep against a test repo to confirm PR creation, comment posting, and workflow dispatch work end-to-end without `gh`

Run `ai-dev-tools-enforce` on all files changed in this phase.

---

## - [ ] Phase 12: Integration Test Against `gestrich/AIDevToolsDemo`

**Skills to read**: `ai-dev-tools-debug`, `ai-dev-tools-pr-radar-debug`

This phase exercises the migrated code against a real GitHub repo to catch regressions that only surface with live data. The demo app at `../AIDevToolsDemo` is already configured as a target repo.

**Setup — confirm the demo repo is configured:**
- Read the chain/sweep config in `../AIDevToolsDemo` to confirm `gestrich/AIDevToolsDemo` is the target
- Confirm a valid `GH_TOKEN` is available in the environment (use `gh auth token` if needed — the gestrich account)

**Run CLI operations that exercise the new GitHub service paths:**

1. **PR creation** — trigger a sweep run against `gestrich/AIDevToolsDemo` via the CLI:
   ```bash
   # Example — adapt to actual CLI entry point
   swift run ai-dev-tools-kit claudechain run --repo gestrich/AIDevToolsDemo ...
   ```
   Verify a draft PR appears in `gestrich/AIDevToolsDemo` via:
   ```bash
   gh pr list --repo gestrich/AIDevToolsDemo --state open
   ```

2. **PR comment** — confirm the post-run summary comment is posted on the created PR:
   ```bash
   gh pr view <number> --repo gestrich/AIDevToolsDemo --comments
   ```

3. **Workflow dispatch** (if applicable) — confirm a `claudechain.yml` workflow run was triggered:
   ```bash
   gh run list --repo gestrich/AIDevToolsDemo --workflow claudechain.yml
   ```

4. **Branch listing / branch deletion** — if the sweep creates and cleans up branches, confirm they appear and are deleted as expected.

**Regression triage:**
- For each failure, use `ai-dev-tools-debug` skill to read logs before digging into code
- Likely regression areas:
  - Token not found / `OctokitClient.fromEnvironment()` returning nil
  - `repoSlug` parse failures (owner/repo split edge cases)
  - HTTP 422 "already_exists" error not caught correctly during PR create recovery
  - Caching TTL causing stale data in list operations
  - Missing `GH_TOKEN` injection for subprocess environments (verify `CredentialResolver` still sets the env var)
- Fix regressions inline in this phase; re-run the CLI commands to confirm each fix

**Success criteria:**
- At least one full sweep run completes end-to-end against `gestrich/AIDevToolsDemo`
- A draft PR appears in the repo with the correct title, body, and labels
- A summary comment is posted on the PR
- No `gh` binary process is spawned (verify by temporarily `chmod -x $(which gh)` or checking process logs)
- `swift test` still passes after any regression fixes
