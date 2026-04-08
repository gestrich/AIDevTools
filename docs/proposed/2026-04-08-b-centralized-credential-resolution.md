## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer Swift app architecture patterns and guidance |
| `ai-dev-tools-architecture` | Reviewing/fixing Swift code for layer violations |
| `ai-dev-tools-swift-testing` | Swift test file conventions |

## Background

GitHub credential resolution is currently scattered across the codebase. Multiple models and use cases independently fall back to keychain scanning when a configured account is absent, silently picking the wrong credentials in multi-org setups. The goals:

1. **Mac app stored credentials are the primary source.** `RepositoryConfiguration.credentialAccount` names which stored credential to use. All features resolve from there.
2. **CLI can use the same keychain.** `SecureSettingsService` already uses `SecurityCLIKeychainStore` on macOS — the infrastructure is in place, it just needs correct wiring.
3. **CLI `--github-token` arg is a strict override.** When provided, it is used directly with no fallback to any other source.
4. **`.env` supports named credentials.** Current flat keys (`GITHUB_TOKEN`, `GITHUB_APP_ID`) work for single-account setups. Named keys (`GITHUB_TOKEN_<account>`, `GITHUB_APP_ID_<account>`) allow per-account credentials matching the same account names stored in the keychain.
5. **All resolution logic lives in `CredentialResolver`.** No fallbacks in models, use cases, or factories. Callers that don't have a configured account get a clear error.

### What gets removed
- `GitHubServiceFactory.resolveAccount()` — scans all keychain accounts and guesses from git remote URL
- `resolveAccount()` fallback in `ClaudeChainModel.makeOrGetGitHubPRService()`
- `resolveAccount()` fallback in `FetchPRListUseCase`
- `?? ""` defaulting in `PRRadarRepoConfig.make()` that converts nil account to empty string silently

### Resolution hierarchy (enforced inside `CredentialResolver`, nowhere else)
```
1. Explicit token (CLI --github-token)           → strict, stop here
2. Named keychain entry  (GITHUB_TOKEN stored for account)
3. Named .env entry      (GITHUB_TOKEN_<account> in .env file)
4. Unnamed .env entry    (GITHUB_TOKEN — convenience for single-account setups)
5. Throw CredentialError.notConfigured           — no silent scanning
```

## - [x] Phase 1: Extend CredentialResolver

**Skills used**: `swift-architecture`
**Principles applied**: Added `CredentialError` enum in its own file following existing single-type file convention. Made `settingsService` optional to support the `withExplicitToken` factory which needs no backing store. Updated `resolveGitHubAppAuth` to treat named env keys, keychain, and unnamed env keys as distinct groups (checked in that order), matching the spec's resolution hierarchy.

**Skills to read**: `swift-architecture`

Update `CredentialService/CredentialResolver.swift`:

- Add named `.env` key support. For a given account, before checking the flat `GITHUB_TOKEN` key, check `GITHUB_TOKEN_<account>` (and equivalents for GitHub App: `GITHUB_APP_ID_<account>`, `GITHUB_APP_INSTALLATION_ID_<account>`, `GITHUB_APP_PRIVATE_KEY_<account>`).
- Add `static func withExplicitToken(_ token: String) -> CredentialResolver` factory. This returns a resolver whose `getGitHubAuth()` always returns `.token(token)` without reading any store.
- Add `func requireGitHubAuth() throws -> GitHubAuth` — wraps `getGitHubAuth()`, throwing `CredentialError.notConfigured(account:)` instead of returning nil. All call sites should use this over the optional form.
- Add `CredentialError` enum to `CredentialService` with at minimum `.notConfigured(account: String)`.

Update the resolution order in `getGitHubAuth()`:
1. GitHub App auth — named env keys first (`GITHUB_APP_ID_<account>`), then keychain, then unnamed env keys
2. Token — named env key (`GITHUB_TOKEN_<account>`), then keychain, then unnamed env key (`GITHUB_TOKEN` / `GH_TOKEN`)
3. Return nil (callers using `requireGitHubAuth()` get an error)

Do not change `createPlatform` or `SecureSettingsService` — they are correct.

## - [x] Phase 2: Delete resolveAccount and Silent Fallbacks

**Skills used**: `ai-dev-tools-architecture`
**Principles applied**: Deleted `resolveAccount()` entirely from `GitHubServiceFactory`. Changed `PRRadarRepoConfig.githubAccount` from `String` to `String?` and removed the `?? ""` silent fallback in `make(from:)`. Updated all 10+ callers across `PRReviewFeature` to `guard let` unwrap and throw `CredentialError.notConfigured(account:)`. Added `CredentialService` to `PRReviewFeature`'s Package.swift dependencies. For best-effort cleanup paths in `AnalyzeUseCase` (branch restoration), used `if let` rather than throwing since those operations are inherently optional. Kept `GitHubServiceFactory.make(token:owner:repo:)` as it is used extensively in production code, not just tests.

**Skills to read**: `ai-dev-tools-architecture`

**`GitHubServiceFactory.swift`**:
- Delete `resolveAccount(repoPath:)` entirely.
- The `createPRService(repoPath:githubAccount:dataPathsService:)` overload stays — it is the correct entry point.
- The `make(token:owner:repo:)` overload hardcodes an App Support cache path; audit callers. If only tests use it, update test setup to inject paths directly and delete the method.

**`ClaudeChainModel.swift`** — `makeOrGetGitHubPRService()`:
- Remove the `resolveAccount()` fallback block.
- If `currentCredentialAccount` is nil or empty, throw `CredentialError.notConfigured` (or surface it as a user-facing error in the model's state).

**`FetchPRListUseCase.swift`**:
- Remove the `config.githubAccount.isEmpty ? resolveAccount() : config.githubAccount` ternary.
- Require `config.githubAccount` to be non-empty; throw if not.

**`PRRadarRepoConfig.swift`** — `make(from:settings:outputDir:...)`:
- Change `githubAccount: info.credentialAccount ?? ""` to `githubAccount: info.credentialAccount`. Update `PRRadarRepoConfig.githubAccount` to `String?`.
- Callers that use `config.githubAccount` now unwrap it explicitly and throw `CredentialError.notConfigured` if nil.

## - [x] Phase 3: Wire CLI --github-token Override

**Skills used**: `swift-architecture`
**Principles applied**: Added `@Option var githubToken: String?` to `RunTaskCommand`, `FinalizeStagedCommand`, `SweepRunCommand`, `StatusCommand`, and `PRRadarCLIOptions` (covering all PRRadar subcommands). Updated `resolveGitHubCredentials` in `CLICredentialSetup` to use `CredentialResolver.withExplicitToken()` when a token is provided. Threaded `explicitToken` through `PRRadarRepoConfig` → `GitHubServiceFactory.resolveToken/create/createGitOps/createPRService` → all PRReviewFeature use case call sites, providing strict override semantics with no fallback.

**Skills to read**: `swift-architecture`

Audit every CLI command that makes GitHub API calls (Claude Chain CLI, PR Radar CLI). For each:

- Add an `@Option(help: "GitHub token (overrides all other credential sources)")` var `githubToken: String?` argument.
- If `githubToken` is provided, construct `CredentialResolver.withExplicitToken(githubToken)` and pass it into the relevant service/use case. Do not fall through to any other source.
- If `githubToken` is nil, construct `CredentialResolver` normally with the account from repo config.

CLI commands to update (verify via grep for `GitHubServiceFactory` or `resolveToken` calls in CLI targets):
- `ClaudeChainCLI/RunTaskCommand.swift` (and other chain CLI commands that call GitHub)
- `AIDevToolsKitCLI/PRRadar/` commands

## - [x] Phase 4: Update Tests

**Skills used**: `ai-dev-tools-swift-testing`
**Principles applied**: Added four new `@Test` functions with descriptive sentence-form names covering: named env key priority, unnamed env key fallback, `withExplicitToken` isolation, and `requireGitHubAuth` error throwing. Each test has one behavior and uses Arrange-Act-Assert structure.

**Skills to read**: `ai-dev-tools-swift-testing`

- Add tests for the new named `.env` key resolution in `CredentialResolverTests` (or create the file if absent):
  - Named key `GITHUB_TOKEN_gestrich` is used when account is `gestrich`
  - Unnamed `GITHUB_TOKEN` is used as fallback when no named key exists
  - `withExplicitToken` always returns the given token, ignoring env and keychain
  - `requireGitHubAuth()` throws `CredentialError.notConfigured` when no credentials exist
- Update any existing tests that relied on `resolveAccount()` or the old fallback behavior.

## - [x] Phase 5: Enforce Standards

**Skills used**: `ai-dev-tools-enforce`, `ai-dev-tools-architecture`, `ai-dev-tools-build-quality`, `ai-dev-tools-code-organization`, `ai-dev-tools-code-quality`, `ai-dev-tools-swift-testing`
**Principles applied**: Added `LocalizedError` conformance to `CredentialError` (with actionable `errorDescription`) and `PRRadarCLIError` (replacing `CustomStringConvertible`). Removed error swallowing in `PostManualCommentUseCase` and `PostSingleCommentUseCase` — both now propagate throws instead of returning `false`; callers already have `do/catch` so behavior is preserved. Removed redundant `logger.error` call in `FetchPRListUseCase` (error already surfaced via `continuation.yield(.failed(...))`). Fixed trailing whitespace in `AnalyzeUseCase`. Added sentence-form `@Test("...")` strings to the seven older test functions in `CredentialResolverTests` that were missing them.

Run the enforce skill against all files changed during this plan before considering the work done.

## - [x] Phase 6: Validate

**Skills used**: `ai-dev-tools-enforce`, `ai-dev-tools-architecture`, `ai-dev-tools-build-quality`, `ai-dev-tools-code-organization`, `ai-dev-tools-code-quality`, `ai-dev-tools-swift-testing`
**Principles applied**: Loaded all six practice skills and analyzed all 51 changed Swift files. `swift build` completed with no errors (only pre-existing resource warnings unrelated to this plan). Key files — `CredentialResolver`, `CredentialError`, `FetchPRListUseCase`, `PostManualCommentUseCase`, `PostSingleCommentUseCase`, and `CredentialResolverTests` — all conform to architecture, code quality, and test conventions. No violations found. Manual smoke tests require a running Mac app and are not automatable.

**Skills to read**: `ai-dev-tools-enforce`

- Run `ai-dev-tools-enforce` against all files changed in this plan.
- Build the full package: `swift build` — no errors.
- Manual smoke test:
  - Mac app: select a repo with `credentialAccount` set → Claude Chain loads chains correctly.
  - Mac app: select a repo with no `credentialAccount` → clear error shown (not a silent wrong-account fetch).
  - CLI: `--github-token <token>` → used directly, no keychain read.
  - CLI: `.env` with `GITHUB_TOKEN_<account>` → correct named credential resolved.
