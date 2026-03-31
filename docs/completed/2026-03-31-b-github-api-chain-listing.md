# GitHub API-Based Chain Listing

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `claude-chain` | ClaudeChain context: branch patterns, label conventions, spec.md structure |

---

## Background

`ListChainsUseCase` reads `claude-chain/*/spec.md` from the **local filesystem** of the checked-out branch. This is fundamentally broken: chains whose `spec.md` lives on a non-default branch (e.g., `bugfix/2026-03/ios-26`) are invisible, and even for chains on the default branch, stale local data can be shown.

The fix added in the previous session (`mergedWithGitHubDiscovery`) discovers missing chains via GitHub label but still can't show their task progress — the ios-26 chains appear as stubs with no task data.

The right solution is to source **all** chain metadata from GitHub, reusing the existing `GitHubPRServiceProtocol` stack:

1. Discover chains by fetching all open PRs and filtering by the `claude-chain-*-*` branch pattern
2. Determine each chain's base branch from its PR's `baseRefName`
3. Fetch `claude-chain/{name}/spec.md` from that base branch via the GitHub contents API
4. Parse with the existing `SpecContent` type

This gives accurate, branch-agnostic data regardless of what is checked out locally.

---

## - [x] Phase 1: Add `fileContent(path:ref:)` to Protocol and Service

Add the file-content method through the existing service stack so `ListChainsFromGitHubUseCase` can depend on `GitHubPRServiceProtocol` (same as `GetChainDetailUseCase`).

**`GitHubAPIServiceProtocol`** (`Sources/Services/GitHubService/GitHubAPIServiceProtocol.swift`):
- Add `func fileContent(path: String, ref: String) async throws -> String`

**`GitHubPRServiceProtocol`** (`Sources/Services/GitHubService/GitHubPRServiceProtocol.swift`):
- Add `func fileContent(path: String, ref: String) async throws -> String`

**`GitHubPRService`** (`Sources/Services/GitHubService/GitHubPRService.swift`):
- Implement `fileContent(path:ref:)` by delegating to `apiClient.fileContent(path:ref:)`

**`GitHubAPIService`** (`Sources/Services/PRRadarCLIService/GitHubAPIService.swift`):
- Already has `getFileContent(path:ref:)` — rename to `fileContent(path:ref:)` to satisfy the protocol. Update the one caller in `getFileSHA` or add a forwarding method.

---

## - [x] Phase 2: Create `ListChainsFromGitHubUseCase`

New file: `Sources/Features/ClaudeChainFeature/usecases/ListChainsFromGitHubUseCase.swift`

```swift
public struct ListChainsFromGitHubUseCase {
    public struct Options: Sendable {
        public let repoPath: URL   // needed to construct Project paths for SpecContent
    }

    private let gitHubPRService: any GitHubPRServiceProtocol

    public init(gitHubPRService: any GitHubPRServiceProtocol) { ... }

    public func run(options: Options) async throws -> [ChainProject]
}
```

**Implementation**:
1. Fetch all open PRs: `gitHubPRService.listPullRequests(limit: 500, filter: PRFilter(state: .open))`
2. Filter to chain PRs: `headRefName` matching the `claude-chain-*-*` pattern via `BranchInfo.fromBranchName`
3. Extract unique project names and their base branch (first-seen wins, same as `DiscoverChainsFromGitHubUseCase`)
4. For each unique project, fetch spec.md:
   ```
   gitHubPRService.fileContent(path: "claude-chain/\(name)/spec.md", ref: baseBranch)
   ```
5. Parse with `SpecContent(project: Project(name: name), content: rawContent)`
6. Build `ChainProject` from parsed spec — or if fetch fails (file not found), build a stub with `isGitHubOnly: true`
7. Return sorted by name

Use `withThrowingTaskGroup` to fetch specs concurrently across projects.

---

## - [x] Phase 3: Update `ClaudeChainModel`

**File**: `Sources/Apps/AIDevToolsKitMac/Models/ClaudeChainModel.swift`

- Remove `listChainsUseCase: ListChainsUseCase` stored property and its `init` parameter
- Remove `mergedWithGitHubDiscovery(_:repoURL:)` private method
- In `loadChains(for:credentialAccount:)`: replace the `listChainsUseCase + mergedWithGitHubDiscovery` call with `ListChainsFromGitHubUseCase(gitHubPRService: service).run(options:)`, reusing `makeOrGetGitHubPRService`
- Since chain loading now requires the GitHub service, it becomes fully async (already inside a `Task`)

---

## - [x] Phase 4: Update `StatusCommand`

**File**: `Sources/Apps/ClaudeChainCLI/StatusCommand.swift`

- When `--github` flag is set: replace `ListChainsUseCase().run() + mergedWithGitHubDiscovery()` with `ListChainsFromGitHubUseCase(gitHubPRService: prService).run(options:)` — `prService` is already created via `makeGitHubPRService`
- Remove `mergedWithGitHubDiscovery(_:repoURL:)` private method from `StatusCommand`
- Local-only mode (no `--github` flag): keep `ListChainsUseCase` unchanged

---

## - [x] Phase 5: Validation

Build the release CLI binary and run end-to-end:

```bash
swift build --package-path /Users/bill/Developer/personal/AIDevTools/AIDevToolsKit -c release

claude-chain status --repo-path <ios-repo-path> --github
```

Verify:
1. All chains from `develop` appear with their full task progress (same as before)
2. `ios-26-ins-policy-*` chain(s) appear with actual task data from spec.md on `bugfix/2026-03/ios-26` — not as stubs
3. No chains show `isGitHubOnly: true` unless spec.md genuinely can't be fetched
4. No regressions on chains already working
