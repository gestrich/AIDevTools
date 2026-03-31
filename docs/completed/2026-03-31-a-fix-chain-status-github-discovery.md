# Fix Chain Status: GitHub Label-Based Chain Discovery

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `claude-chain` | Context on ClaudeChain automated PR chains and CLI usage |

---

## Background

The `claude-chain status --github` command discovers chains in two steps: first by scanning the local filesystem for `claude-chain/{name}/spec.md` files, then enriching those locally-found chains with GitHub PR data (filtered by branch name prefix).

The iOS repo contains many open draft PRs belonging to claude chains. Many of those chains are **missing from the CLI status output** because their `spec.md` files live on non-default branches (each chain's spec tracks its own feature branch), so a filesystem scan from the default branch never finds them.

The fix is to supplement local filesystem discovery with GitHub label-based discovery: fetch all PRs tagged with the `claudechain` label, parse the head branch names (`claude-chain-{name}-{hash}`) to extract unique chain project names, and include those in the status output even when no local `spec.md` is present.

---

## - [x] Phase 1: Audit the Discrepancy

**Skills used**: `claude-chain`
**Principles applied**: Used `chain-status.sh` (paginated GraphQL) and direct `gh pr list` to gather GitHub ground truth; compared against `claude-chain status` CLI output (local filesystem scan).

**Findings:**

**Chains visible on GitHub** (8 unique projects via `claudechain` label):

| Project Name | Base Branch | Open PRs |
|---|---|---|
| `ios-26-ins-policy-AFWXBriefs-to-Diag` | `bugfix/2026-03/ios-26` | 8 |
| `remove-file-spaces-enroute` | `develop` | 10 |
| `remove-file-spaces-enterprise-content` | `develop` | 1 |
| `remove-file-spaces-enterprise-flights` | `develop` | 8 |
| `remove-file-spaces-foundation-ios` | `develop` | 6 |
| `remove-file-spaces-map-integrations` | `develop` | 7 |
| `remove-file-spaces-postflight` | `develop` | 6 |
| `remove-file-spaces-weather` | `develop` | 3 |

**Chains in CLI output** (19 projects via local filesystem on `develop`): All `develop`-targeting chains above appear, plus additional fully-completed chains (`remove-file-spaces-designkit`, `remove-file-spaces-labs`, etc.) and in-progress ones (`claude-skills`, `layered-architecture`).

**Missing chain**: `ios-26-ins-policy-AFWXBriefs-to-Diag` — 8 open PRs on GitHub, but `spec.md` only exists on branch `bugfix/2026-03/ios-26`, not on `develop`.

**Root cause confirmed**: Local filesystem discovery reads only the currently checked-out branch. Chains whose `spec.md` lives on a non-default branch are invisible to the CLI.

**Skills to read**: `claude-chain`

Run the following commands against the iOS repo to establish ground truth and identify which chains are missing:

1. Get all open chain PRs from GitHub using the label:
   ```
   gh pr list --repo <ios-repo> --label claudechain --state open --json number,title,headRefName,baseRefName,isDraft --limit 500
   ```
2. From the output, extract unique chain project names by parsing `headRefName` using the pattern `claude-chain-{project-name}-{8-char-hash}`.
3. Note each unique `baseRefName` — this reveals which chains target non-default branches.
4. Run `claude-chain status --repo-path <ios-repo> --github` and record which chains appear.
5. Cross-reference the two lists: chains visible on GitHub but absent from CLI output are the ones that need to be fixed.

**Expected outcome**: A concrete list of missing chain names and their target base branches, confirming the local-filesystem-only discovery is the root cause.

---

## - [x] Phase 2: Add GitHub Label-Based Chain Discovery Use Case

**Skills used**: none
**Principles applied**: Placed `DiscoveredChain` struct in the same file as the use case (single use site, no premature abstraction). Used `repo: String` (GitHub owner/name) rather than a local path since this use case is purely GitHub-based. Reused `GitHubOperations.listPullRequests` static method and `BranchInfo.fromBranchName` directly. Kept first-encountered `baseRefName` per project (simplest deduplication). Properties ordered alphabetically per project convention.

Create a new use case `DiscoverChainsFromGitHubUseCase` in:
`AIDevToolsKit/Sources/Features/ClaudeChainFeature/usecases/DiscoverChainsFromGitHubUseCase.swift`

This use case should:
- Accept a `repoPath: String` and `label: String` (defaulting to `Constants.defaultLabel`)
- Call `PRService.getProjectPrs(label:)` (or the underlying `GitHubOperations.listPullRequests`) to fetch all open PRs with the given label
- For each PR, parse `headRefName` using `BranchInfo.fromBranchName(_:)` to extract `projectName`
- Return an array of `DiscoveredChain` — a new lightweight struct:
  ```swift
  struct DiscoveredChain {
      let projectName: String
      let baseRefName: String   // what branch the chain's PRs target
      let openPRCount: Int
  }
  ```
- Deduplicate by `projectName` (keep the most common `baseRefName` or the first encountered)

Technical note: `BranchInfo.fromBranchName` already parses `claude-chain-{name}-{hash}` — reuse it directly.

---

## - [x] Phase 3: Create Lightweight ChainProject from Discovered Chains

**Skills used**: none
**Principles applied**: Added `isGitHubOnly: Bool = false` to `ChainProject` keeping existing callers unaffected. Placed the `fromDiscoveredChain` factory extension in the feature layer (only place that knows about both `ChainProject` and `DiscoveredChain`).

Chains found only via GitHub (no local `spec.md`) need a `ChainProject` representation so `StatusCommand` can display them. Add a static factory on `ChainProject` (or a free function in the feature layer):

```swift
extension ChainProject {
    static func fromDiscoveredChain(_ discovered: DiscoveredChain) -> ChainProject
}
```

This produces a `ChainProject` with:
- `name` = `discovered.projectName`
- `specPath` = empty/placeholder (mark as GitHub-only)
- `tasks` = empty array (no local spec to parse)
- A new `isGitHubOnly: Bool = true` flag so the status display can note "spec not on current branch"

Also update the `ChainProject` model in `AIDevToolsKit/Sources/Services/ClaudeChainService/Models.swift` to add the `isGitHubOnly` property (default `false` so existing code is unaffected).

---

## - [x] Phase 4: Update StatusCommand to Merge Local and GitHub-Discovered Chains

**Skills used**: none
**Principles applied**: Made `projects` mutable (`var`) so the merged list can replace the local-only scan. Added `mergedWithGitHubDiscovery` helper that calls `DiscoverChainsFromGitHubUseCase` and appends GitHub-only projects not already in the local list. Moved `isEmpty` check inside each branch so it runs after the potential merge. Made `ChainProject.fromDiscoveredChain` `public` to fix cross-module visibility. Added `(spec on non-default branch)` annotation in `printEnrichedProjectList` for `isGitHubOnly` projects.

Modify `AIDevToolsKit/Sources/Apps/ClaudeChainCLI/StatusCommand.swift`:

- When the `--github` flag is set, run `DiscoverChainsFromGitHubUseCase` in parallel with the existing `ListChainsUseCase` filesystem scan
- Merge results: start with locally-discovered projects, then add any project names from GitHub discovery that are **not already in the local list** as `ChainProject.fromDiscoveredChain(_:)`
- Pass the merged list to the existing `GetChainDetailUseCase` enrichment loop (no change needed there — it already fetches PRs by branch prefix for each project name)
- In the status display, mark GitHub-only chains with a note like `(spec on non-default branch)` after the project name so Bill can distinguish them

This change is additive — local-only runs (no `--github` flag) are unchanged.

---

## - [x] Phase 5: Validation

**Skills used**: none
**Principles applied**: Built release binary and ran end-to-end validation against iOS repo. Discovered stray `[]` output caused by `runGhCommand` creating `CLIClient()` with default `printOutput: true`; fixed with `CLIClient(printOutput: false)`. All 8 GitHub-discovered chains appear in output; `ios-26-ins-policy-AFWXBriefs-to-Diag` now visible with `(spec on non-default branch)` label; 19 pre-existing chains unaffected.

Build the CLI and verify the fix end-to-end:

```bash
# Build
swift build --package-path /Users/bill/Developer/personal/AIDevTools/AIDevToolsKit -c release

# Re-run status with GitHub enrichment
claude-chain status --repo-path <ios-repo> --github

# Re-run the gh audit query
gh pr list --repo <ios-repo> --label claudechain --state open --json number,headRefName,baseRefName --limit 500 | jq '[.[].headRefName | capture("claude-chain-(?P<name>.+)-[0-9a-f]{8}") | .name] | unique | sort'
```

Verify that:
1. Every chain project name extracted by the `jq` command above appears in the `claude-chain status` output
2. Chains with local spec files show their task progress as before
3. GitHub-only chains (no local spec) show their PR count and enrichment data (build status, review status) and are labeled as spec-on-non-default-branch
4. No regressions in chains that were already working before the fix
