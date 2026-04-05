## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | 4-layer architecture rules, dependency direction, service placement |
| `ai-dev-tools-swift-testing` | Swift Testing conventions for writing tests |

## Background

`GitHubChainProjectSource.listChains()` always calls `repository(useCache: false)`, making a live network call every time. `ClaudeChainModel` (Mac UI) calls `listChains(source: .remote)` on every view load, so the chain list view always shows a spinner with no stale-data fallback.

The existing `GitHubPRServiceProtocol` already supports `repository(useCache: Bool)` — used in `PRAcquisitionService` which calls `updateRepository()` then reads with `useCache: true`. We need to thread `useCache` up through the stack so `ClaudeChainModel` can show cached projects immediately on first appearance, then update with fresh data.

CLI callers (`StatusCommand`, `MCPCommand`, etc.) always want fresh data and should default to `useCache: false` with no changes needed at their call sites.

## Phases

## - [x] Phase 1: Add `useCache` to `ChainProjectSource` and implementations

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Added `useCache: Bool` to the protocol requirement and both implementations. Swift protocols don't support default parameter values, and protocol extension methods aren't accessible via `any` existentials, so updated the three call sites in `ClaudeChainService.swift` to pass `useCache: false` explicitly — keeping behavior identical until Phase 2 threads the parameter properly.

**Skills to read**: `ai-dev-tools-architecture`

Update the protocol and both implementations:

**`ClaudeChainService/ChainProjectSource.swift`**
```swift
func listChains(useCache: Bool) async throws -> ChainListResult
```

**`ClaudeChainFeature/GitHubChainProjectSource.swift`**
```swift
public func listChains(useCache: Bool) async throws -> ChainListResult {
    let defaultBranch = try await gitHubPRService.repository(useCache: useCache).defaultBranch
    // rest unchanged
}
```

**`ClaudeChainService/LocalChainProjectSource.swift`**
Add `useCache: Bool` parameter, ignore it — local file reads have no cache concept.

## - [ ] Phase 2: Thread `useCache` through `ClaudeChainService`

**Skills to read**: (none additional)

Update `listChains` in `ClaudeChainFeature/ClaudeChainService.swift`:

```swift
public func listChains(source: ChainSource, kind: ChainKind = .all, useCache: Bool = false) async throws -> ChainListResult
```

Pass `useCache` through to the underlying `source.listChains(useCache:)` call. Default of `false` means all existing CLI call sites require no changes.

## - [ ] Phase 3: Update `ClaudeChainModel` to show cache then refresh

**Skills to read**: (none additional)

In `AIDevToolsKitMac/Models/ClaudeChainModel.swift`, update `loadChains(for:credentialAccount:)` to use a cache-first pattern:

1. Attempt `listChains(source: .remote, useCache: true)` — if it returns non-empty projects, immediately show them via `state = .loaded(cached.projects)`
2. Then fetch `listChains(source: .remote, useCache: false)` for fresh data and update state
3. On network error: if cached data was already shown, leave the state as `.loaded` (don't replace with `.error`); if no cached data was shown, set `state = .error`

## - [ ] Phase 4: Validation

**Skills to read**: `ai-dev-tools-swift-testing`

1. `swift build` — no errors, no new warnings
2. Existing `ClaudeChainServiceListingTests` still pass — add a test verifying `useCache: true` is forwarded to the stub source
3. Manual: Open chain view in Mac app — on second load, projects appear immediately before network call completes
4. Manual: CLI `claude-chain status` still returns fresh data
