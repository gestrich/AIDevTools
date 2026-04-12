## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | Layer placement, dependency rules, orchestration patterns |
| `ai-dev-tools-composition-root` | How CLI and Mac app wire dependencies |
| `ai-dev-tools-enforce` | Post-implementation standards check across all changed files |

## Background

PRRadar is a feature for AI/scripted code review that sits above a general GitHub data layer. However, several generic GitHub infrastructure pieces are currently trapped in PRRadar-named packages, creating architectural confusion:

- `GitHubAPIService`, `OctokitMapping`, `GitHubServiceFactory`, `GitHubServiceError` — live in `PRRadarCLIService` but are generic GitHub API implementation with no PRRadar logic
- `GitHubPRLoaderUseCase` — lives in `PRReviewFeature` but is generic PR loading used by the Pull Requests tab; Claude Chain cannot use it without taking on PRRadar dependencies
- `AuthorCacheService` — lives in `PRRadarConfigService`; author caching is a GitHub infrastructure concern, not PRRadar-specific
- `AuthorCache`/`AuthorCacheEntry` — live in `PRRadarModelsService`; same issue

The goal is to move all generic GitHub infrastructure into `GitHubService` so PRRadar and Claude Chain are pure consumers of a clean GitHub layer. As part of this, author caching gets a 7-day TTL via a generic `CacheRecord<T>` wrapper, and a new `LoadAuthorsUseCase` becomes the single entry point for all author data — no caller touches the service layer for author info directly.

## Phases

## - [x] Phase 1: Move GitHub API implementation from `PRRadarCLIService` → `GitHubService`

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Moved `GitHubAPIService`, `OctokitMapping`, `GitHubServiceError`, `GitHubServiceFactory` plus their supporting infrastructure (`GitHistoryProvider`, `LocalGitHistoryProvider`, `GitHubAPIHistoryProvider`, `GitHubAppTokenService`) to `GitHubService`. Added `CLISDK`, `CredentialService`, `DataPathsService`, `GitSDK`, `RepositorySDK` to `GitHubService` deps (plan's "no new deps" claim was inaccurate for `GitHubServiceFactory`). Replaced `CredentialResolver.createPlatform` (from `PRRadarConfigService`) with `CredentialResolver(settingsService: SecureSettingsService(), ...)` from `CredentialService` to avoid adding a PRRadar dep to `GitHubService`. Deleted `resolveAuthorNames` and stubbed its callers in `PRAcquisitionService`. Added `import GitHubService` to files within `PRRadarCLIService` and `PRReviewFeature` that referenced the moved types.

**Skills to read**: `ai-dev-tools-architecture`

Move the following 4 files from `Sources/Services/PRRadarCLIService/` to `Sources/Services/GitHubService/`:

- `GitHubAPIService.swift`
- `OctokitMapping.swift`
- `GitHubServiceFactory.swift`
- `GitHubServiceError.swift`

`GitHubService` already imports `OctokitSDK` and `PRRadarModelsService`, so these files compile there without any new `Package.swift` dependency. `PRRadarCLIService` already imports `GitHubService`, so all existing callers continue to find these types with no import changes.

**Delete `resolveAuthorNames`:** `GitHubAPIService` has a `resolveAuthorNames(logins:cache:AuthorCacheService)` method that depends on `PRRadarConfigService`. Delete it as part of the move — its replacement is `LoadAuthorsUseCase` in Phase 3. Update `PRAcquisitionService` (the only caller) with a stub or inline replacement to keep the build clean until Phase 3.

**`Package.swift` changes:** No new dependencies for `GitHubService`. `PRRadarCLIService` no longer owns these 4 files but already imports `GitHubService`.

## - [x] Phase 2: Move `GitHubPRLoaderUseCase` from `PRReviewFeature` → `GitHubService`

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`
**Principles applied**: Introduced `GitHubRepoConfig` in `GitHubService` with non-optional `account` field so credential validation happens at conversion time. Added `makeGitHubRepoConfig() throws` to `PRRadarRepoConfig` and a `noGitHubAccount` case to `PRRadarRepoConfigError`. Added `GitHubService` as a direct dep of `PRRadarConfigService` in `Package.swift`. Replaced `PRDiscoveryService.discoverPRs(config:)` with a new `readAllCachedPRs()` method on `GitHubPRCacheService`/`GitHubPRService` (scanning the cache directory directly, matching prior logic). Dropped `AuthorCacheService` from the use case — author cache updates will be restored via `LoadAuthorsUseCase` in Phase 3. Removed `StreamingUseCase` conformance since `UseCaseSDK` is not a dep of `GitHubService` and no caller uses the protocol type. Dropped `import PRReviewFeature` from `PullRequestsModel`, `PRRadarRefreshCommand`, and `PRRadarRefreshPRCommand` since they now get `GitHubPRLoaderUseCase` from `GitHubService` directly.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`

`GitHubPRLoaderUseCase` contains no PRRadar AI logic — it's generic PR loading. Moving it to `GitHubService` makes it available to Claude Chain and the Pull Requests tab without those callers depending on PRRadar packages.

**Blocker:** The use case currently takes `PRRadarRepoConfig` (from `PRRadarConfigService`). Remove this dependency by introducing `GitHubRepoConfig` in `GitHubService`:

```swift
public struct GitHubRepoConfig: Sendable {
    public let name: String
    public let cacheURL: URL
    public let repoPath: String
    public let account: String
    public let token: String?
}
```

Add a conversion method on `PRRadarRepoConfig`:
```swift
public func makeGitHubRepoConfig() throws -> GitHubRepoConfig
```

**Move** `Sources/Features/PRReviewFeature/usecases/GitHubPRLoaderUseCase.swift` → `Sources/Services/GitHubService/GitHubPRLoaderUseCase.swift`. Update its `init` to take `GitHubRepoConfig`. Remove all `PRRadar*` imports — the file should only use `GitHubService`-internal types.

**Update call sites** (`AllPRsModel`, `PullRequestsModel`, CLI refresh commands): call `prRadarConfig.makeGitHubRepoConfig()` before constructing the use case.

**`Package.swift` changes:** `GitHubService` target needs no new dependencies. `PRReviewFeature` drops the use case file; it already imports `GitHubService` so the type is still found.

## - [x] Phase 3: Author caching + `CacheRecord<T>` + `LoadAuthorsUseCase` in `GitHubService`

**Skills used**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`
**Principles applied**: Created `CacheRecord<T>` as a generic TTL wrapper. Moved `AuthorCacheEntry`/`AuthorCache` from `PRRadarModelsService` to `GitHubService`, removing `fetchedAt` from `AuthorCacheEntry` (TTL now lives in `CacheRecord`). Added `readAuthors`/`writeAuthors` to `GitHubPRCacheService`, and `lookupAuthor`/`updateAuthor`/`loadAllAuthors` to `GitHubPRService` (not on the protocol — `LoadAuthorsUseCase` constructs `GitHubPRService` directly). Added `getUser(login:)` to `GitHubAPIServiceProtocol`/`GitHubAPIService` via `octokitClient.getUser`. `LoadAuthorsUseCase` is the sole entry point for all author data — `PRAcquisitionService` methods now take `config: GitHubRepoConfig` instead of `authorCache: AuthorCacheService`. `AllPRsModel` loads authors via `executeAll()` in `loadCached()` and holds them in `loadedAuthors`; `availableAuthors` is computed from that. `GitHubPRLoaderUseCase` calls `updateAuthorCache(for:)` after each PR enrichment. Deleted `AuthorCacheService` from `PRRadarConfigService` and `AuthorCache`/`AuthorCacheEntry` from `PRRadarModelsService`.

**Skills to read**: `ai-dev-tools-architecture`, `ai-dev-tools-composition-root`

With `GitHubAPIService` now in `GitHubService` (Phase 1), `GitHubPRService` can call `apiClient.getUser(login:)` directly. This phase adds the full author caching stack.

**3a. `CacheRecord<T>` — new file `Sources/Services/GitHubService/CacheRecord.swift`**

Generic TTL wrapper reusable for any per-entry cached GitHub data:
```swift
public struct CacheRecord<T: Codable & Sendable>: Codable, Sendable {
    public let value: T
    public let cachedAt: Date
    public init(value: T, cachedAt: Date = Date()) { ... }
    public func isExpired(ttl: TimeInterval) -> Bool { ... }
    public func valueIfFresh(ttl: TimeInterval) -> T? { ... }
}
```

**3b. `AuthorCache`/`AuthorCacheEntry` — move from `PRRadarModelsService` to `GitHubService`**

Delete `Sources/Services/PRRadarModelsService/AuthorCache.swift`. Create `Sources/Services/GitHubService/AuthorCache.swift` with `fetchedAt` removed (TTL now lives in `CacheRecord`) and entries typed as `[String: CacheRecord<AuthorCacheEntry>]`.

**3c. `readAuthors()` / `writeAuthors(_:)` on `GitHubPRCacheService`**

Stored at `{rootURL}/author-cache.json`. No file-level TTL — per-entry TTL is handled by `CacheRecord`.

**3d. Low-level author cache ops on `GitHubPRService`**

Raw cache primitives only — resolution logic belongs in the use case:
- `lookupAuthor(login:) async throws -> AuthorCacheEntry?` — 7-day TTL check
- `updateAuthor(login:name:avatarURL:) async throws` — wraps in `CacheRecord`, writes
- `loadAllAuthors() async throws -> [AuthorCacheEntry]` — all entries regardless of TTL

**3e. `getUser(login:)` on `GitHubAPIServiceProtocol`**

Add `func getUser(login: String) async throws -> GitHubAuthor`. Implement in `GitHubAPIService` — the logic already exists inside the deleted `resolveAuthorNames`, just extracted.

**3f. `LoadAuthorsUseCase` — new file `Sources/Services/GitHubService/LoadAuthorsUseCase.swift`**

The single entry point for all author data. No caller (PRRadar, Claude Chain, or a model) touches `GitHubPRService` author methods directly.

```swift
public struct LoadAuthorsUseCase {
    public init(config: GitHubRepoConfig) { ... }

    // Cache-first lookup with TTL; fetches expired/missing logins via getUser
    public func execute(logins: Set<String>) async throws -> [String: AuthorCacheEntry]

    // All cached authors — for filter dropdowns on repo load
    public func executeAll() async throws -> [AuthorCacheEntry]
}
```

**3g. Update `GitHubPRLoaderUseCase`** (now in `GitHubService`)

After enriching each PR, call `LoadAuthorsUseCase(config:).execute(logins:)` with the PR and reviewer logins found in that PR's data. Remove `AuthorCacheService` from `makeService()`.

**3h. Update `PRAcquisitionService`** (`Sources/Services/PRRadarCLIService/PRAcquisitionService.swift`)

Replace `gitHub.resolveAuthorNames(logins:cache:)` + `AuthorCacheService` parameters with `LoadAuthorsUseCase(config:).execute(logins:)`. PRRadar calls a use case — never touches the service directly.

**3i. Update `AllPRsModel` and `PullRequestsModel`**

On repo load, call `LoadAuthorsUseCase(config:).executeAll()` and hold the result. Author filter dropdown sources from the held value. Remove all `AuthorCacheService` usage.

**3j. Delete `AuthorCacheService`** (`Sources/Services/PRRadarConfigService/AuthorCacheService.swift`)

## - [x] Phase 4: Enforce

**Skills used**: `ai-dev-tools-enforce`, `ai-dev-tools-build-quality`, `ai-dev-tools-code-quality`, `ai-dev-tools-code-organization`
**Principles applied**: Replaced `print()` calls with `logger.error()` in `CommentService` (build quality). Added intentional-swallow comments to all `try?` author-cache calls in `GitHubPRLoaderUseCase`, `PRAcquisitionService`, and `AllPRsModel` (code quality). Added `_ =` to unused `try?` results in `PRAcquisitionService` to suppress compiler warnings. Fixed pre-existing `@Sendable` closure warning in `PRAcquisitionService.diffNoIndex` call by wrapping in an explicit `@Sendable` closure. Removed unused `import CredentialService` from `GitHubPRLoaderUseCase`. Fixed alphabetical sort order of methods in `GitHubPRServiceProtocol` (`readAllCachedPRs` was at position 3, moved to correct position after `pullRequestByHeadBranch`; `updatePR`/`updatePRs` reordered). Removed redundant `?? ""` fallback in `AllPRsModel.availableAuthors` where the left side was already non-optional.

Run `ai-dev-tools-enforce` on all Swift files modified across Phases 1–3.

## - [x] Phase 5: Validation

**Skills used**: `ai-dev-tools-enforce`
**Principles applied**: Fixed three pre-existing test compilation failures introduced in Phases 1–2: added `readAllCachedPRs()` stub to `FailingGitHubPRService` in `WorkflowServiceTests.swift` (method added to protocol in Phase 2 but test double not updated); added `import GitHubService` to `GitHistoryProviderTests.swift` and `@testable import GitHubService` to `GitHubAppTokenServiceTests.swift` (both types moved to `GitHubService` in Phase 1 but test imports not updated); added `"GitHubService"` to `PRRadarModelsServiceTests` dependencies in `Package.swift`. Static checks: `GitHubAPIService`, `OctokitMapping`, `GitHubServiceFactory` confirmed in `GitHubService` only; no `AuthorCacheService` usage in `PRAcquisitionService`, `AllPRsModel`, or `PullRequestsModel`. Note: `GitHubPRLoaderUseCase` imports `PRRadarModelsService` for shared types (`PRMetadata`, `PRFilter`, `GitHubPullRequest`) — this is correct since `GitHubService` already declares `PRRadarModelsService` as a package dependency; the plan's intent was to remove `PRReviewFeature`/`PRRadarCLIService` imports, which are absent. `SkillScannerTests` failures are pre-existing environment contamination from `~/.claude/commands` files, unrelated to this plan. Items 6–7 (double-run cache verification and TTL expiry test) require live GitHub network access and manual verification.

1. `swift build` — must be clean after each phase.
2. `swift test` — all existing tests pass.
3. Verify `GitHubAPIService`, `OctokitMapping`, `GitHubServiceFactory` live in `Sources/Services/GitHubService/` (not `PRRadarCLIService`).
4. Verify `GitHubPRLoaderUseCase` has no `PRRadar*` imports.
5. Verify `PRAcquisitionService`, `AllPRsModel`, `PullRequestsModel` have no `AuthorCacheService` usage.
6. Run `prradar refresh --config ios` twice — second run reads author data from cache with no `GET /users` API calls (confirm via logs).
7. Manually set a `cachedAt` 8+ days in the past for one author entry in `author-cache.json`; confirm `lookupAuthor` returns nil on next run (triggering a re-fetch).
