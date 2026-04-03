## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-app-architecture:swift-architecture` | 4-layer architecture — changes span SDK, Service, Feature layers |
| `logging` | Add logging to new cache paths for debuggability |

## Background

Loading chains for `ios-auto` exhausts the REST API core quota (5000/day) because `ListChainsFromGitHubUseCase` makes ~50 REST calls on every load — 1 repo lookup, ~5 pages of PRs, 1 directory listing, plus 21 spec fetches and 21 config fetches (one per project). There is no caching at any layer for directory listings, file content, or branch HEAD pointers.

The fix is to use GitHub's Git Tree API to fetch all blob SHAs for the `claude-chain/` directory in **2 REST calls per branch** instead of 2N, then serve file content from a content-addressed blob cache. This caching belongs in the existing `GitHubPRCacheService` / `GitHubPRService` layer — not as a chain-specific concern. TTL support also belongs at that generic layer.

Key existing structure:
- `OctokitClient` — raw REST/GraphQL, no caching
- `GitHubAPIService` — wraps OctokitClient, maps to domain models, no caching
- `GitHubPRService` — wraps `GitHubAPIService` + `GitHubPRCacheService`, has `useCache:` pattern for PRs/comments/reviews/repository
- `GitHubPRCacheService` — disk-based JSON cache, **no TTL**, **no tree/blob/directory caching**
- `GitHubPRServiceProtocol` — consumed by use cases; `fileContent` and `listDirectoryNames` are on the protocol but currently bypass caching entirely

## - [x] Phase 1: Add `getBranchHead` and `getGitTree` to OctokitClient and GitHubAPIService

**Skills used**: none
**Principles applied**: Defined `BranchHead` and `GitTreeEntry` as public types in `OctokitSDK` (alongside `OctokitClient`) and added `OctokitSDK` as a dependency of `GitHubService` so the protocol could reference these types without circular imports. Also extended `ContentsMetadata` with optional `content`/`encoding` fields for `getFileContentWithSHA`. New `GitHubPath` cases added alphabetically (`branch`, `gitTree`).

**Skills to read**: none

Add two new REST operations to `OctokitClient`:

**`getBranchHead(branch:) -> BranchHead`**
Calls `GET /repos/{owner}/{repo}/branches/{branch}`.
Returns a new `public struct BranchHead: Codable, Sendable { let commitSHA: String; let treeSHA: String }`.
Decoded from the response shape `{ "commit": { "sha": "...", "commit": { "tree": { "sha": "..." } } } }`.

**`getGitTree(treeSHA:) -> [GitTreeEntry]`**
Calls `GET /repos/{owner}/{repo}/git/trees/{treeSHA}?recursive=1`.
Returns `[GitTreeEntry]` where `public struct GitTreeEntry: Codable, Sendable { let path: String; let sha: String; let type: String }` (type is `"blob"` or `"tree"`).

Add `GitHubPath` cases for both endpoints in `OctokitClient.swift`.

Expose both on `GitHubAPIServiceProtocol` and implement on `GitHubAPIService`.

Also extend `ContentsMetadata` (currently only `sha`) to include `content: String?` and `encoding: String?` (both optional for safety), and add:

**`getFileContentWithSHA(path:, ref:) -> (sha: String, content: String)`**
Uses JSON accept header (same as `getFileSHA`) but decodes the base64 `content` field too, returning both in one call. Expose on protocol and implement.

Files:
- `OctokitSDK/OctokitClient.swift`
- `PRRadarCLIService/GitHubAPIService.swift`
- `GitHubService/GitHubAPIServiceProtocol.swift`

## - [x] Phase 2: Add TTL support and new cache entries to `GitHubPRCacheService`

**Skills used**: none
**Principles applied**: Extended `readFile<T>` with optional `ttl: TimeInterval?` that checks `.modificationDate` via `FileManager.attributesOfItem`; all existing call sites pass no TTL and keep current behaviour. Added `readBranchHead/writeBranchHead` (under `branches/`), `readGitTree/writeGitTree` (under `trees/`, JSON), and `readBlob/writeBlob` (under `blobs/`, plain `.txt`) directly to `GitHubPRCacheService`. Branch names are sanitised (replace `/`, `:`, spaces with `-`). Blob files skip JSON encoding entirely since the content is already a UTF-8 string. Added `import OctokitSDK` to bring `BranchHead` and `GitTreeEntry` into scope.

**Skills to read**: none

The existing `readFile<T>` helper checks only for file existence. Extend it with an optional TTL:

```swift
func readFile<T: Decodable>(at url: URL, ttl: TimeInterval? = nil) throws -> T?
```

If `ttl` is provided, check `FileManager.default.attributesOfItem(atPath:)[.modificationDate]`. Return `nil` (cache miss) if the file is older than TTL seconds. All existing call sites omit `ttl` and keep current behaviour.

Add cache storage for the three new data types:

**Branch HEAD** — keyed by branch name, short TTL (caller provides, suggested 5 min):
```swift
func readBranchHead(branch: String) throws -> BranchHead?
func writeBranchHead(_ head: BranchHead, branch: String) throws
```
Stored at `{rootURL}/branches/{sanitised-branch-name}.json`.

**Git tree** — keyed by tree SHA, **no TTL** (content-addressed, immutable):
```swift
func readGitTree(treeSHA: String) throws -> [GitTreeEntry]?
func writeGitTree(_ entries: [GitTreeEntry], treeSHA: String) throws
```
Stored at `{rootURL}/trees/{treeSHA}.json`.

**File blob** — keyed by blob SHA, **no TTL** (immutable):
```swift
func readBlob(blobSHA: String) throws -> String?
func writeBlob(_ content: String, blobSHA: String) throws
```
Stored at `{rootURL}/blobs/{blobSHA}.txt`.

Files:
- `GitHubService/GitHubPRCacheService.swift`
- `GitHubService/GitHubPRService.swift` (expose new methods, also add TTL param where needed in `readFile` call sites)

## - [ ] Phase 3: Expose new cache-backed methods on `GitHubPRService` and protocol

**Skills to read**: none

Add to `GitHubPRServiceProtocol`:

```swift
func branchHead(branch: String, ttl: TimeInterval) async throws -> BranchHead
func gitTree(treeSHA: String) async throws -> [GitTreeEntry]
func fileBlob(blobSHA: String, path: String, ref: String) async throws -> String
```

Implement in `GitHubPRService` with the cache-first pattern already used for PRs/reviews:

- `branchHead`: read cache with TTL → on miss fetch from API and write cache
- `gitTree`: read cache (no TTL) → on miss fetch from API and write cache
- `fileBlob`: read blob cache → on miss call `getFileContentWithSHA`, store blob, return content

Also wire `listDirectoryNames` through a cache in `GitHubPRService`. Key: `{rootURL}/dirs/{ref}-{sanitised-path}.json` with a short TTL (same as branch HEAD). Currently it bypasses the cache entirely.

Files:
- `GitHubService/GitHubPRServiceProtocol.swift`
- `GitHubService/GitHubPRService.swift`

## - [ ] Phase 4: Rewrite `ListChainsFromGitHubUseCase` to use tree API

**Skills to read**: none

Replace the current per-project file fetches with the tree-based approach:

**Current flow per branch:**
1. `listDirectoryNames("claude-chain", ref: branch)` → N project names (1 call)
2. For each project: `fileContent(spec.md)` + `fileContent(config.yaml)` (2N calls)
3. **Total: 1 + 2N calls** (42 + 1 = 43 calls for 21 projects)

**New flow per branch:**
1. `branchHead(branch:, ttl: 300)` → commit SHA + tree SHA (1 call, cached 5 min)
2. `gitTree(treeSHA:)` → all blob SHAs under `claude-chain/` (1 call, content-addressed cache)
3. Filter entries to `claude-chain/*/spec.md` and `claude-chain/*/config.yaml`
4. Extract project names from paths (replaces `listDirectoryNames`)
5. For each file: `fileBlob(blobSHA:, path:, ref:)` → content from blob cache or single fetch on miss
6. **Total: 2 calls + M fetch calls** where M = number of files changed since last run (usually 0)

The `discoverNonDefaultBranches` method (which calls `listPullRequests(limit: 500)`) is unchanged for now — that's a separate optimisation.

Update `ListChainsFromGitHubUseCase` to:
- Inject `GitHubPRServiceProtocol` as before (protocol now has the new methods)
- Use the tree approach described above
- Derive project names from tree paths instead of a directory listing call

Files:
- `ClaudeChainFeature/usecases/ListChainsFromGitHubUseCase.swift`

## - [ ] Phase 5: Validation

**Skills to read**: `logging`

**CLI smoke test** — confirm chains load without REST errors:
```bash
cd AIDevToolsKit && swift run ai-dev-tools-kit claude-chain status --repo /Users/bill/Developer/work/ios-auto
```
Wait for rate limit to reset (check `gh api rate_limit`) then run and confirm 21 projects load.

**Cache verification** — after first load, check cache files exist:
```bash
ls ~/Desktop/ai-dev-tools/ios-auto/github-cache/branches/
ls ~/Desktop/ai-dev-tools/ios-auto/github-cache/trees/
ls ~/Desktop/ai-dev-tools/ios-auto/github-cache/blobs/ | wc -l
```

**Second load** — confirm REST `core` quota barely moves (should be ~8 calls per branch regardless of project count).

**Log review** — add `logger.debug` in `GitHubPRService` for cache hits vs API calls on `branchHead`, `gitTree`, and `fileBlob`. Verify hit rate is high after first run.
