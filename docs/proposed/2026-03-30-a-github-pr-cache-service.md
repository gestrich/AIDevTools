## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture with dependency rules and async use case patterns |
| `pr-radar-debug` | CLI commands, PRRadar internals, and Mac app debugging |

## Background

PRRadar stores GitHub PR metadata (PR info, comments, repo data) under its own output directory alongside analysis artifacts (diff, prepare, evaluate, report). The metadata portion — `gh-pr.json`, `gh-comments.json`, `gh-repo.json` — is really a generic GitHub PR cache, not PRRadar-specific. Any feature that works with PRs (e.g., ClaudeChain enriched view from `2026-03-29-a-chain-pr-status-enrichment.md`) would benefit from tapping into a shared, well-managed cache rather than each feature building its own.

The goal is to:

1. Create a `GitHubPRService` in the Services layer that owns all GitHub PR metadata caching and API access — a single interface any client uses for PR data.
2. Store cached PR metadata under a new top-level `github/<repo-slug>/` path in `DataPathsService` instead of inside PRRadar's output directory.
3. Add observation support so clients are notified when cache data changes.
4. Support both full-sweep updates (PRRadar's existing behavior) and targeted single/list updates (for detail views).
5. Migrate PRRadar to use this service rather than managing its own PR cache.

The commit-hash-based analysis paths (`analysis/<commit>/diff`, `prepare`, `evaluate`, `report`) remain PRRadar-owned — only the `metadata/` layer moves to the new service.

## Phases

## - [x] Phase 1: Add `github` path to `DataPathsService`

**Skills used**: `swift-architecture`
**Principles applied**: Added `github(repoSlug: String)` case to `ServicePath` enum in alphabetical order, following the existing `prradarOutput(String)` pattern for parameterized paths.

**Skills to read**: `swift-architecture`

Add a new `github` case to the `ServicePath` enum in `DataPathsService.swift`:

```swift
case github(repoSlug: String)
```

With `relativePath`:
```swift
case .github(let repoSlug):
    return "github/\(repoSlug)"
```

This creates `<rootPath>/github/<owner>-<repo>/` on first access, matching the convention of `prradarOutput(String)` which uses `prradar/repos/<name>`. The repo slug should be the normalized `owner-repo` form (replace `/` with `-` to be filesystem-safe).

No other changes in this phase — just the path registration.

## - [x] Phase 2: Create `GitHubPRService` module

**Skills used**: `swift-architecture`
**Principles applied**: Created `GitHubService` target in the Services layer with four files: `GitHubAPIClientProtocol` (abstracts the API client so `PRRadarCLIService` can conform later without circular deps), `GitHubPRCache` actor (internal, owns file I/O and emits changes via `nonisolated let stream`), `GitHubPRServiceProtocol` (public interface), and `GitHubPRService` struct (public implementation). Used `AsyncStream.makeStream()` with `nonisolated let` on the actor to allow synchronous stream access from the struct's `init`. Dependencies: `DataPathsService`, `OctokitSDK`, `PRRadarModelsService` per spec.

**Skills to read**: `swift-architecture`

Create a new Swift target `GitHubService` in the Services layer (alongside `PRRadarCLIService`, `ClaudeChainService`, etc.). This module owns all GitHub PR metadata caching and API access.

**Storage layout** (mirrors existing `metadata/` structure, just relocated):
```
<rootPath>/github/<repo-slug>/<pr-number>/
  gh-pr.json
  gh-comments.json
  gh-repo.json
  image-url-map.json
  images/
```

**`GitHubPRCache` actor** — internal, manages file I/O:
- `readPR(number:) throws -> GitHubPullRequest?`
- `readComments(number:) throws -> GitHubPullRequestComments?`
- `readRepository() throws -> GitHubRepository?`
- `writePR(_:number:) throws`
- `writeComments(_:number:) throws`
- `writeRepository(_:) throws`
- Holds a `rootURL: URL` (the `github/<repo-slug>/` directory from `DataPathsService`)
- Emits change events by continuing a `AsyncStream<Int>` (PR number that changed); callers observe this stream

**`GitHubPRServiceProtocol`** — public protocol:
```swift
public protocol GitHubPRServiceProtocol: Sendable {
    func pullRequest(number: Int, useCache: Bool) async throws -> GitHubPullRequest
    func comments(number: Int, useCache: Bool) async throws -> GitHubPullRequestComments
    func updatePR(number: Int) async throws
    func updatePRs(numbers: [Int]) async throws
    func updateAllPRs() async throws -> [GitHubPullRequest]
    func changes() -> AsyncStream<Int>
}
```

**`GitHubPRService` struct** — public implementation:
- Injected with: `GitHubPRCache` (actor), `GitHubAPIClient` (existing `GitHubService` from `PRRadarCLIService`, renamed or extracted to `OctokitSDK` layer or kept as-is via protocol)
- `pullRequest(number:useCache:)`: returns cached value if `useCache && cache.readPR(number:) != nil`, else fetches from API, writes to cache, emits change
- `updateAllPRs()`: fetches open PRs list from API, writes each to cache, emits changes, returns full list
- `updatePR(number:)` and `updatePRs(numbers:)`: fetch individually, write to cache, emit per-PR changes
- `changes()`: returns the `AsyncStream<Int>` from `GitHubPRCache`

**`AuthorCacheService`** can stay where it is for now — the new service accepts it as an optional dependency for comment author resolution (same as `PRAcquisitionService` today).

Add `GitHubService` target to `Package.swift` with dependencies on `OctokitSDK`, `PRRadarModels` (for shared model types), and `DataPathsService`.

## - [x] Phase 3: Migrate PRRadar to use `GitHubPRService`

**Skills used**: `swift-architecture`, `pr-radar-debug`
**Principles applied**: Added `dataRootURL: URL?` to `RepositoryConfiguration` and a `gitHubCacheURL` computed property (reads repo slug from git config). Made `GitHubService` (PRRadarCLIService) conform to `GitHubAPIClientProtocol` and exposed `repoSlug`. Extended `GitHubPRServiceProtocol` with `repository(useCache:)`, `updateRepository()`, `writePR(_:number:)`, and `writeComments(_:number:)`. `PRAcquisitionService` now accepts an optional `GitHubPRServiceProtocol` — when set, all metadata writes go through the shared cache; when nil, legacy write behavior is preserved. Added config-aware overloads to `PRDiscoveryService` (`discoverPRs(config:)`, `loadGitHubPR(config:prNumber:)`, `loadComments(config:prNumber:)`) that prefer the shared cache over the PRRadar output path. All read sites in use cases and the Mac app model updated to use these config-aware helpers.

**Skills to read**: `swift-architecture`, `pr-radar-debug`

Update `PRAcquisitionService` in `PRRadarCLIService` to accept a `GitHubPRServiceProtocol` instead of directly writing `gh-pr.json`, `gh-comments.json`, `gh-repo.json` itself.

Changes:
- `PRAcquisitionService.acquire()` calls `gitHubPRService.updatePR(number:)` for metadata instead of fetching and writing files inline
- `refreshComments()` calls `gitHubPRService.comments(number:useCache:false)` (forces fresh fetch, which writes to cache automatically)
- Read PR metadata via `gitHubPRService.pullRequest(number:useCache:true)` where PRRadar previously read `gh-pr.json` directly

`PRDiscoveryService` updates:
- Currently scans PRRadar's `outputDir` for numeric subdirectories containing `metadata/gh-pr.json`
- Add an overload that reads from the `GitHubPRCache` path (`github/<repo-slug>/<pr-number>/gh-pr.json`) so PRRadar can discover PRs from the shared cache
- Keep backward compat by supporting both paths during transition if needed (but prefer single path)

PRRadar's existing update-all mechanism (the CLI `update` command or equivalent) now calls `gitHubPRService.updateAllPRs()` — same behavior, just delegating to the service.

The `analysis/<commit>/` subdirectories (diff, prepare, evaluate, report) and `PRRadarPhasePaths` are **unchanged** — they remain PRRadar-owned and live in the PRRadar output directory.

## - [x] Phase 4: Wire observation into PRRadar and ClaudeChain models

**Skills used**: `swift-architecture`
**Principles applied**: Added `gitHubPRService` and `changesTask` properties to `AllPRsModel`. `makeGitHubPRService()` lazily creates and caches a `GitHubPRService` (using `GitHubServiceFactory` for the API client); `startObservingChanges(service:)` starts a `Task` iterating `service.changes()` and calls `updateMetadata`/`loadSummary` on the affected `PRModel` when a PR number is emitted. `FetchPRListUseCase.execute()` accepts an optional `gitHubPRService` parameter so `AllPRsModel.refresh()` can pass the shared service instance, ensuring writes from the use case flow through the subscribed stream. Added `GitHubService` as a dependency to both `AIDevToolsKitMac` and `ClaudeChainFeature` in `Package.swift`.

**Skills to read**: `swift-architecture`

**PRRadar Mac model** (`PRRadarModel` or equivalent in the Apps layer):
- On init or when a repo is selected, subscribe to `gitHubPRService.changes()`
- When a PR number is emitted, re-read that PR's data and update observable state
- Pattern per `swift-architecture`: use a `Task` to iterate the `AsyncStream` and update `@Observable` model properties

**ClaudeChain integration** (light touch, enables `2026-03-29-a-chain-pr-status-enrichment.md`):
- `GetChainDetailUseCase` (planned in that doc) can accept a `GitHubPRServiceProtocol` for fetching PR metadata from the shared cache
- No full integration in this plan — just ensure `GitHubPRService` is injectable and available to `ClaudeChainFeature`
- Add `GitHubService` as a dependency of `ClaudeChainFeature` in `Package.swift`

## - [x] Phase 5: Validation

**Skills used**: `pr-radar-debug`
**Principles applied**: Ran all CLI validation checks against the `PRRadar-TestRepo` config. Confirmed metadata files are written to `~/Desktop/ai-dev-tools/github/gestrich-PRRadar-TestRepo/<pr-number>/` (new path), analysis artifacts remain in `prradar/repos/PRRadar-TestRepo/<pr-number>/analysis/<commit>/diff/`, full-sweep `refresh` fetched all 16 PRs into the github cache, targeted `refresh-pr 3` updated only PR 3, and `status` correctly discovered PRs via the new cache path.

Build verification:
- `swift build` for `AIDevToolsKit` and all CLI targets — no regressions

Functional checks via CLI:
- Run PRRadar `acquire` on a known PR and verify `gh-pr.json`, `gh-comments.json`, `gh-repo.json` now appear under `<dataRoot>/github/<repo-slug>/<pr-number>/` instead of the old PRRadar output path
- Confirm `analysis/<commit>/` artifacts remain in the PRRadar output directory (unchanged)
- Run PRRadar's full-sweep update and verify all open PRs update and the observation stream emits their numbers
- Run targeted update for a single PR number and verify only that PR is re-fetched
- Verify PRDiscovery still finds PRs correctly from the new path
- Confirm `DataPathsService.path(for: .github(repoSlug:))` creates the correct directory on first use
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find new features architected as afterthoughts and refactor them to integrate cleanly with the existing system, and make the necessary code changes

**Skills used**: `swift-architecture`, `pr-radar-debug`
**Principles applied**: Found three afterthoughts where new integration points were bypassed. (1) `resolvePRRadarConfig` reconstructed `RepositoryConfiguration` without `dataRootURL` when overriding `diffSource`, so any CLI `--diff-source` flag silently disabled the GitHub cache — fixed by forwarding `dataRootURL`. (2) `FetchPRListUseCase` manually recomputed the cache URL from `config.dataRootURL + gitHub.repoSlug` instead of using `config.gitHubCacheURL`, the canonical integration point added for exactly this purpose — replaced with `config.gitHubCacheURL`. (3) `SyncPRUseCase` had the same duplication — same fix applied.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Identify the architectural layer for every new or modified file; read the reference doc for that layer before reviewing anything else, and make the necessary code changes

**Skills used**: `swift-architecture`
**Principles applied**: Read `layers.md` before reviewing any file. Mapped every new/modified file to its layer: `GitHubService` module (4 files) → Services ✓; `DataPathsService`, `PRRadarConfigService`, `PRRadarCLIService` changes → Services ✓; `FetchPRListUseCase`, `SyncPRUseCase` → Features ✓; `AllPRsModel`, `PRRadarCLISupport` → Apps ✓. Confirmed no upward dependencies, `@Observable` only in Apps layer, use cases are structs. `GitHubAPIClientProtocol` correctly placed in Services (not SDKs) because it uses `PRRadarModelsService` types that SDKs cannot import. No layer violations found; build passes.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find code placed in the wrong layer entirely and move it to the correct one, and make the necessary code changes

**Skills used**: `swift-architecture`, `python-architecture:identifying-layer-placement`
**Principles applied**: Reviewed all new/modified files across phases 1–7. Found one layer violation: `FetchReviewCommentsUseCase` duplicated the GitHub cache URL path-building logic from the Services layer (`RepositoryConfiguration.gitHubCacheURL`) directly in the Features layer — the same afterthought pattern Phase 6 fixed in `FetchPRListUseCase` and `SyncPRUseCase` but missed here. Fixed by replacing the manual `dataRootURL + repoSlug` computation with `config.gitHubCacheURL`. Also removed `DataPathsService` and `OctokitSDK` from the `GitHubService` target in `Package.swift` — both were declared as dependencies but never imported by any file in the module.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find upward dependencies (lower layers importing higher layers) and remove them, and make the necessary code changes

**Skills used**: `swift-architecture`
**Principles applied**: Reviewed all `import` statements in every new and modified file across layers. Checked Services for Feature/App imports, and SDKs for Service/Feature imports. Found zero upward dependency violations — all dependencies correctly flow downward: Apps→Features→Services→SDKs. The new `GitHubService` module (Services) imports only `PRRadarModelsService` (also Services, lateral dependency); `PRRadarCLIService` and `PRReviewFeature` import only Services and SDKs. Build passes clean.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find `@Observable` or `@MainActor` outside the Apps layer and move it up, and make the necessary code changes

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Grepped all files changed in phases 1–9 for `@Observable` and `@MainActor`. Found zero violations — all occurrences are in the Apps layer (`AllPRsModel.swift`, `WorkspaceModel.swift`). The new `GitHubService` module (Services), `PRReviewFeature` use cases (Features), and all modified Services files contain no `@Observable` or `@MainActor` annotations. No code changes required.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find multi-step orchestration that belongs in a use case and extract it, and make the necessary code changes

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Found one violation: Phase 4 added `makeGitHubPRService()` to `AllPRsModel` — a multi-step async method that created the `GitHubPRService`, then started observation, then passed the service into `FetchPRListUseCase`. This put service creation orchestration in the App layer when it belongs in the use case. Fixed by moving `GitHubPRService` creation into `FetchPRListUseCase.execute()` and returning it in a new `FetchPRListResult` output type. `AllPRsModel.refresh()` now calls the use case without a pre-created service and subscribes to observation from the returned service in the `.completed` case. Removed `makeGitHubPRService()` from `AllPRsModel`.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find feature-to-feature imports and replace with a shared Service or SDK abstraction, and make the necessary code changes

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Scanned all Feature target dependencies in Package.swift and all `import` statements in every Swift source file under `Sources/Features/`. Found zero feature-to-feature imports — every Feature target depends only on Services and SDKs. `ClaudeChainFeature` imports `GitHubService` (Service), `ClaudeChainService` (Service), and SDKs; `PRReviewFeature` imports `PRRadarCLIService`, `PRRadarConfigService`, `PRRadarModelsService` (all Services) and SDKs. No code changes required.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find SDK methods that accept or return app-specific or feature-specific types and replace them with generic parameters, and make the necessary code changes

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Reviewed all 19 SDK targets (104 Swift source files). No SDK file imports any Service, Feature, or App module — every import is Foundation, another SDK, or an external package. All public method signatures use only primitive types, SDK-local types (e.g. `ReviewCommentData`, `CompareResult`), or OctoKit/OctoKit-wrapped types. No violations found; no code changes required.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find SDK methods that orchestrate multiple operations and split them into single-operation methods, and make the necessary code changes

**Skills used**: none
**Principles applied**: Scanned all SDK files changed in phases 1–13 via `git log`. Zero SDK files (under `Sources/SDKs/`) were added or modified in any phase — all new code landed in Services (`GitHubService`, `PRRadarCLIService`), Features, and Apps layers. No SDK methods that orchestrate multiple operations were introduced; no code changes required.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find SDK types that hold mutable state and refactor to stateless structs, and make the necessary code changes

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Scanned all SDK targets for type declarations (class, actor) and stored `var` properties. Found pre-existing actors in `AnthropicSDK`, `AIOutputSDK`, and `ConcurrencySDK`, and a class in `ClaudeChainSDK` — all predating this task chain. Zero SDK files under `Sources/SDKs/` were added or modified in phases 1–14; all new code landed in Services (`GitHubService`, `PRRadarCLIService`), Features, and Apps layers. The new `GitHubPRCache` actor is correctly placed in Services (appropriate for stateful utilities), not in SDKs. No code changes required.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find error swallowing across all layers and replace with proper propagation, and make the necessary code changes

**Skills used**: none
**Principles applied**: Found two error swallowing issues in `PRAcquisitionService`. (1) `downloadImages()` used a catch-all `catch { return [:] }` that silently swallowed network and I/O errors (including `fetchBodyHTML` failures) — fixed by making the method `async throws` and removing the catch block, so callers see real failures. (2) `refreshComments()` used `try?` on `fetchResolvedReviewCommentIDs(number:)` with a fallback to `[]`, silently discarding a real network error that affects review thread resolution state — fixed by changing to plain `try`. All other `try?` occurrences in scope were either pre-existing pre-phase code, filesystem directory scans where empty-on-missing is correct, or per-item graceful degradation (e.g., `resolveAuthorNames` falling back to login per-user).
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Verify use case types are structs conforming to `UseCase` or `StreamingUseCase`, not classes or actors, and make the necessary code changes

**Skills used**: `ai-dev-tools-review`
**Principles applied**: Scanned all 73 use case files across all Feature targets (PRReviewFeature, MarkdownPlannerFeature, ChatFeature, SkillBrowserFeature, EvalFeature, ArchitecturePlannerFeature, ClaudeChainFeature, CredentialFeature, PipelineFeature) plus two in DataPathsService. Every type declaration is `public struct ... : UseCase` or `public struct ... : StreamingUseCase` — zero classes or actors found. No code changes required.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Verify type names follow the `<Name><Layer>` convention and rename any that don't, and make the necessary code changes

**Skills used**: `swift-architecture`
**Principles applied**: Found two naming violations in the `GitHubService` module. (1) `GitHubPRCache` (internal actor, Services layer) lacked the `Service` suffix — renamed to `GitHubPRCacheService`. (2) `GitHubAPIClientProtocol` used `Client` rather than the layer-appropriate `Service` suffix — renamed to `GitHubAPIServiceProtocol`, with the conformance in `PRRadarCLIService/GitHubService.swift` updated accordingly. Supporting output types (`FetchPRListResult`, `SyncSnapshot`) are data types scoped to their use cases and correctly carry no layer suffix.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Verify both a Mac app model and a CLI command consume each new use case, and make the necessary code changes

**Skills used**: `swift-app-architecture:swift-architecture`
**Principles applied**: Audited all three use cases modified in this chain. `FetchPRListUseCase` and `SyncPRUseCase` already had both Mac model consumers (`AllPRsModel`, `PRModel`) and CLI commands (`refresh`, `refresh-pr`/`sync`). `FetchReviewCommentsUseCase` had four Mac model call sites in `PRModel` but no direct CLI command — it was only reachable via `PostCommentsUseCase`. Added `PRRadarViolationsCommand` (`violations`) that calls `FetchReviewCommentsUseCase` directly to list pending violations for a PR, with `--refresh` flag for GitHub fetch and `--min-score` option.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Split files that define multiple unrelated types into one file per type, and make the necessary code changes

**Skills used**: none
**Principles applied**: Found five files with multiple unrelated types and split each into one file per type. (1) `DataPathsService.swift` had `DataPathsError`, `ServicePath`, and `DataPathsService` — split into three files. (2) `GitHubServiceFactory.swift` had `GitHubServiceError` and `GitHubServiceFactory` — split into two files. (3) `FetchPRListUseCase.swift` had `FetchPRListResult` and `FetchPRListUseCase` — split into two files. (4) `SyncPRUseCase.swift` had `SyncSnapshot` and `SyncPRUseCase` — split into two files. (5) `AllPRsModel.swift` had `AuthorOption` and `AllPRsModel` — split into two files. Left `PRRadarViolationsCommand.swift` intact (its `extension ReviewComment.State` is a display helper tightly coupled to the command output) and `GitHubPRCacheService.swift` intact (its `private extension JSONEncoder` is a file-scoped helper, not a separate type).
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Move supporting enums and nested types below their primary type, not above it, and make the necessary code changes

**Skills used**: none
**Principles applied**: Found two files where nested supporting enums appeared above the primary type's properties and methods. (1) `AllPRsModel.swift` had `State`, `RefreshAllState`, and `AnalyzeAllState` declared at the top of the class body before all properties — moved to the bottom of the class. (2) `PRAcquisitionService.swift` had `AcquisitionError` and `AcquisitionResult` declared before the struct's properties and init — moved to the bottom of the struct.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find fallback values that hide failures and suppressed errors — remove or replace both with proper propagation, and make the necessary code changes

**Skills used**: none
**Principles applied**: Audited all `try?`, `?? default`, and catch patterns in the new/modified code from phases 1-21. All `try?` usages are for cache reads where nil is the correct fallback (consistent with pre-existing patterns in `loadGitHubPR(outputDir:)` and `discoverPRs(outputDir:)`). All `?? 0` usages are on comment/review counts where 0 is correct when cache is absent. All `?? []` are on collections that can legitimately be empty. Phase 16 already removed the two genuinely-swallowing cases in `PRAcquisitionService` (`downloadImages` and `refreshComments`). No new violations found; no code changes required.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Remove backwards compatibility shims added before release — there is no backwards compatibility obligation for unreleased code, and make the necessary code changes

**Skills used**: none
**Principles applied**: Found five backwards compatibility shims added during the GitHub cache migration (phases 1–3). (1) `PRDiscoveryService` had `discoverPRs(outputDir:)`, `discoverPR(number:outputDir:)`, and `loadGitHubPR(outputDir:)` legacy methods plus fallback paths in the `config:` overloads — removed the legacy methods entirely and simplified the `config:` overloads to return nil/empty when `gitHubCacheURL` is nil. (2) `PRAcquisitionService` accepted an optional `gitHubPRService` with entire `else` branches that wrote directly to PRRadar output dir — made `gitHubPRService` non-optional and removed both `else` branches; also removed the now-unused `outputDir` parameter from `refreshComments()`. (3) `SyncPRUseCase` and `FetchReviewCommentsUseCase` created an optional service via `config.gitHubCacheURL.map { ... }` with `PhaseOutputParser`/legacy-write fallbacks — replaced with a `guard let` that throws `noDataRoot` if unconfigured. (4) `FetchPRListUseCase` had a large `else` branch that manually fetched, resolved authors, and wrote directly to the PRRadar metadata dir — removed entirely, leaving only the cache path. (5) `FetchPRListResult.gitHubPRService` was optional to accommodate the old path that had no service — made non-optional; `AllPRsModel` updated to remove the `if let` guard.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Replace `String`, `[String: Any]`, and raw dictionary types in APIs with proper typed models, and make the necessary code changes

**Skills used**: none
**Principles applied**: Found two issues. (1) `FetchPRListUseCase.execute()` had `limit: String? = nil` and `repoSlug: String? = nil` parameters that were vestiges of the old implementation — both unused in the new body that calls `updateAllPRs()`. Removed both parameters and updated callers in `PRRadarRefreshCommand` (also removed the now-dead `--limit` CLI option) and `AllPRsModel`. (2) `PRRadarViolationsCommand` (new in Phase 19) used `[String: Any]` + `JSONSerialization` to build JSON output — replaced with a private `ViolationOutput: Codable` struct and `JSONEncoder`.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Replace optional types with non-optional where the value must be present, and make the necessary code changes

**Skills used**: none
**Principles applied**: Found one issue: `PRAcquisitionService.refreshComments(prNumber:authorCache:)` and `acquire(prNumber:outputDir:authorCache:)` both declared `authorCache: AuthorCacheService? = nil`, but every caller provides an `AuthorCacheService()` instance — nil was never a valid state. Made both parameters non-optional and removed the `if let authorCache` guards, collapsing the inner `if let prLogin = pullRequest.author?.login` check (which remains optional, coming from the GitHub API model).
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Remove AI-changelog-style comments and replace with concise documentation or remove entirely, and make the necessary code changes

**Skills used**: none
**Principles applied**: Found four changelog-style comments. (1) `Config.swift` had a multi-line NOTE explaining a domain layer violation and referencing "Phase 2 migration" — removed entirely. (2) `PRAcquisitionService.acquire()` docstring described where files "remain" vs where they "are written to" in migration language — trimmed to a single-line description. (3) `PRAcquisitionService.acquire()` body had three `// ---` section dividers narrating code phases — removed. (4) `ArtifactService.getAssigneeAssignments()` had `// Now TaskMetadata has assignee property available` above commented-out dead code — removed the comment, dead loop, and unused `findProjectArtifacts` call, replacing the body with `return [:]`. Also removed migration guidance from `PRRadarPhasePaths.phaseDirectory()` docstring.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Find duplicated logic and consolidate into a single shared implementation, and make the necessary code changes

**Skills used**: none
**Principles applied**: Found two duplications. (1) `JSONEncoder.prettyPrinted` was defined as a `private extension` in both `GitHubPRCacheService.swift` (GitHubService module) and `PRAcquisitionService.swift` (PRRadarCLIService module) — moved to a new `JSONEncoder+Formatting.swift` in `PRRadarModelsService` (imported by both modules) as a `public extension`, removing both local copies. (2) An identical `noDataRoot` error enum with the same `errorDescription` was defined privately in `FetchPRListUseCase`, `SyncPRUseCase`, and `FetchReviewCommentsUseCase` — consolidated into a new `RepositoryConfigurationError` type in `PRRadarConfigService` and a new `requireGitHubCacheURL() throws -> URL` method on `RepositoryConfiguration`, replacing all three guards and private enums with a single `try config.requireGitHubCacheURL()` call.
## - [x] Code Review: Review the code changes that have been made in these tasks for the following: Replace force unwraps with proper optional handling, and make the necessary code changes

**Skills used**: none
**Principles applied**: Found one force unwrap introduced in Phase 19's new `PRRadarViolationsCommand`: `String(data: data, encoding: .utf8)!`. Since `JSONEncoder` always produces valid UTF-8, replaced with the non-optional `String(decoding: data, as: UTF8.self)`. All other `!` usages in the phase-chain code were boolean `!` operators, not force unwraps.
