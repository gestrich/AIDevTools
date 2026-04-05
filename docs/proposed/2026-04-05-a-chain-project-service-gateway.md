## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | 4-layer architecture rules, dependency direction, service placement |
| `ai-dev-tools-code-quality` | Avoid force unwraps, raw strings, fallback values, duplicated logic, etc. |

## Background

Currently callers construct `ListChainsUseCase(source: LocalChainProjectSource(...))` or `ListChainsUseCase(source: GitHubChainProjectSource(...))` directly, scattering source-selection decisions across every call site. There is no single entry point for chain project operations — callers must understand and choose among `LocalChainProjectSource`, `GitHubChainProjectSource`, `ListChainsUseCase`, `ProjectService`, etc.

`ClaudeChainService` will be extended to also serve as the single gateway for chain project discovery. It will:
1. Hold both a local source and a remote (GitHub) source as properties
2. Expose a single `listChains(source:kind:)` method parameterised by enums; `source` is required, `kind` defaults to `.all`
3. Expose `detectLocalProjects(fromChangedPaths:)` replacing `ProjectService.detectLocalProjectsFromMerge`

```swift
public enum ChainSource { case local, remote }
public enum ChainKind   { case spec, sweep, all }
```

Call sites to migrate:
- `StatusCommand` → `service.listChains(source: .remote)`
- `PrepareCommand` → `service.listChains(source: .local)`
- `RunTaskCommand` → `service.listChains(source: .local)`
- `MCPCommand` → `service.listChains(source: .remote)`
- `ClaudeChainModel` → `service.listChains(source: .remote)`
- `ProjectService.detectLocalProjectsFromMerge` → `service.detectLocalProjects(fromChangedPaths:)`

`ClaudeChainService.buildPipeline` and `buildFinalizePipeline` also hardcode `"claude-chain"` as the project directory — these should be fixed to use local chain discovery.

## Phases

## - [x] Phase 1: Extend `ClaudeChainService`

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Added `ChainSource` and `ChainKind` enums as public `Sendable` types. Made `localSource`/`remoteSource` optional internally so the existing pipeline-building init (`init(client:git:)`) remains valid — callers using `buildPipeline`/`buildFinalizePipeline` don't need sources; `listChains`/`detectLocalProjects` throw a `LocalizedError` with an actionable message if called on an under-initialized instance. Used `any GitHubPRServiceProtocol` (not the concrete type) in the convenience init to match the existing pattern in `GitHubChainProjectSource`.

**Skills to read**: `ai-dev-tools-architecture`

Add `localSource` and `remoteSource` properties to `ClaudeChainService` and expand its init:

```swift
public struct ClaudeChainService {
    private let client: any AIClient
    private let git: GitClient
    private let localSource: any ChainProjectSource
    private let remoteSource: any ChainProjectSource

    // Testable init — inject custom sources
    public init(
        client: any AIClient,
        git: GitClient = GitClient(),
        localSource: any ChainProjectSource,
        remoteSource: any ChainProjectSource
    ) {
        self.client = client
        self.git = git
        self.localSource = localSource
        self.remoteSource = remoteSource
    }

    // Convenience init for production use
    public init(client: any AIClient, git: GitClient = GitClient(), repoPath: URL, prService: GitHubPRService) {
        self.init(
            client: client,
            git: git,
            localSource: LocalChainProjectSource(repoPath: repoPath),
            remoteSource: GitHubChainProjectSource(gitHubPRService: prService)
        )
    }

    // MARK: - Chain listing

    public func listChains(source: ChainSource, kind: ChainKind = .all) async throws -> ChainListResult {
        // Fetch from local or remote source
        // Filter by kind (spec: kindBadge == nil, sweep: kindBadge != nil, all: no filter)
        ...
    }

    // MARK: - Project detection from changed file paths

    /// Returns Projects for any changed file paths that match a known chain spec path.
    public func detectLocalProjects(fromChangedPaths paths: [String]) async throws -> [Project] {
        let result = try await listLocalChains()
        return result.projects
            .filter { project in paths.contains(project.specPath) }
            .map { Project(name: $0.name, basePath: $0.basePath) }
            .sorted { $0.name < $1.name }
    }
}
```

Note: `detectLocalProjects(fromChangedPaths:)` uses the local source since changed-file detection happens during a GitHub Actions run with the repo checked out.

## - [x] Phase 2: Migrate call sites

**Skills used**: none
**Principles applied**: Added a `localSource`-only convenience init to `ClaudeChainService` so local-only callers (`PrepareCommand`, `RunTaskCommand`) don't need a `prService`. Remote callers (`StatusCommand`, `MCPCommand`) use the existing `init(client:git:repoPath:prService:)`. `ClaudeChainModel` uses `activeClient` already in scope. Added `import ClaudeCLISDK` where `ClaudeProvider()` is used as a minimal AIClient placeholder for commands that only need listing.

Update each caller to construct a `ClaudeChainService` and call the appropriate method:

| Call site | File | Old pattern | New pattern |
|-----------|------|-------------|-------------|
| `StatusCommand` | `ClaudeChainCLI/StatusCommand.swift` | `ListChainsUseCase(source: GitHubChainProjectSource(...)).run()` | `service.listChains(source: .remote)` |
| `PrepareCommand` | `ClaudeChainCLI/PrepareCommand.swift` | `ListChainsUseCase(source: LocalChainProjectSource(...)).run()` | `service.listChains(source: .local)` |
| `RunTaskCommand` | `ClaudeChainCLI/RunTaskCommand.swift` | `ListChainsUseCase(source: LocalChainProjectSource(...)).run()` | `service.listChains(source: .local)` |
| `MCPCommand` | `AIDevToolsKitCLI/MCPCommand.swift` | `ListChainsUseCase(source: GitHubChainProjectSource(...)).run()` | `service.listChains(source: .remote)` |
| `ClaudeChainModel` | `AIDevToolsKitMac/Models/ClaudeChainModel.swift` | `ListChainsUseCase(source: GitHubChainProjectSource(...)).run()` | `service.listChains(source: .remote)` |

Each caller needs to construct a `ClaudeChainService`. For remote callers, `GitHubServiceFactory.createPRService(repoPath:)` is already the pattern for getting a `prService` (see `StatusCommand` and `MCPCommand`).

## - [x] Phase 3: Migrate `ProjectService.detectLocalProjectsFromMerge`

**Skills used**: none
**Principles applied**: Converted `ParseEventCommand` from `ParsableCommand` to `AsyncParsableCommand` (and `run()` to `async throws`) so the two helper methods that call project detection could become `async throws` and use `service.detectLocalProjects(fromChangedPaths:)`. Constructed `ClaudeChainService` in `run()` using `ClaudeProvider()` + `LocalChainProjectSource(repoPath:)` with the current working directory, matching the pattern already established in `PrepareCommand`. Deleted `ProjectService.swift` and `ProjectServiceTests.swift` (no remaining methods).

Replace `ProjectService.detectLocalProjectsFromMerge(changedFiles:)` with `ClaudeChainService.detectLocalProjects(fromChangedPaths:)`. Find all callers of `ProjectService.detectLocalProjectsFromMerge` and update them to use the service.

Delete `ProjectService` if it has no remaining methods.

## - [x] Phase 4: Fix hardcoded `"claude-chain"` in `ClaudeChainService`

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Added a private `findLocalProject(named:repoPath:)` helper that uses `self.localSource` if set, otherwise creates a `LocalChainProjectSource` from `options.repoPath` inline — so `buildPipeline`/`buildFinalizePipeline` work regardless of how the service was initialized. Added `projectNotFound` to `ChainServiceError` with an actionable `errorDescription`.

**Skills to read**: `ai-dev-tools-architecture`

`ClaudeChainService.buildPipeline` and `buildFinalizePipeline` hardcode:
```swift
let chainDir = options.repoPath.appendingPathComponent("claude-chain").path
let project = Project(name: ..., basePath: (chainDir as NSString).appendingPathComponent(...))
```

Fix by using `listLocalChains()` to find the project by name and derive `basePath` from `ChainProject.basePath`. Add `repoPath` + `prService` to `ChainRunOptions` if not already present, or pass a `ClaudeChainService` directly.

## - [x] Phase 5: Remove now-unused types

**Skills used**: none
**Principles applied**: Deleted `ListChainsUseCase` and its test file (no production callers remained; test file used an outdated API that no longer matched the implementation). Added a `init(client:git:repoPath:)` convenience init to `ClaudeChainService` so callers constructing a local-only service no longer need to import or construct `LocalChainProjectSource` directly. Updated `RunTaskCommand`, `PrepareCommand`, and `ParseEventCommand` to use the new init. After these changes, `LocalChainProjectSource` and `GitHubChainProjectSource` are only referenced inside `ClaudeChainService.swift` and their own definition files.

After all call sites are migrated:
- Delete `ListChainsUseCase` if it has no remaining callers outside `ClaudeChainService`
- Confirm `LocalChainProjectSource` and `GitHubChainProjectSource` are only referenced inside `ClaudeChainService` (they become implementation details)

## - [x] Phase 6: Validation

**Skills used**: `ai-dev-tools-swift-testing`
**Principles applied**: Fixed pre-existing compilation errors in test files (`Project(name:)` missing `basePath`, `Project.fromBranchName` and `Project.findAll` not found) by restoring the `Project(name:)` convenience init (default `basePath = "claude-chain/\(name)"`), adding `Project.fromBranchName` and `Project.findAll` static methods (thin wrappers over `BranchInfo` and filesystem scanning), and correcting a stale test assertion in `testFromConfigPathWithDifferentBaseDir`. Added `ClaudeChainServiceListingTests.swift` with 10 Swift Testing tests covering `listChains(source:kind:)` and `detectLocalProjects(fromChangedPaths:)` using stub sources.

1. `swift build` — no errors, no new warnings ✓
2. Grep confirms: no direct construction of `ListChainsUseCase`, `LocalChainProjectSource`, or `GitHubChainProjectSource` outside `ClaudeChainService` ✓
3. Grep confirms: `ProjectService` is deleted ✓
4. Manual: `claude-chain status` still shows remote chains correctly
5. Manual: `claude-chain prepare PROJECT_NAME` still finds the correct project locally
