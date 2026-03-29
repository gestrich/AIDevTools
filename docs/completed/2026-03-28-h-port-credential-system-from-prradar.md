> **2026-03-29 Obsolescence Evaluation:** Completed. All phases marked [x] complete and credential system components exist in the codebase: KeychainSDK, CredentialService, CredentialFeature, CLI commands, and Mac app UI. The credential system has been successfully ported from PRRadar to AIDevTools.

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture (Apps, Features, Services, SDKs) with placement guidance |
| `swift-swiftui` | Model-View patterns — `@Observable` models, enum-based state, dependency injection |

## Background

AIDevTools currently stores the Anthropic API key in plaintext `UserDefaults` (Mac app) or reads it from the `ANTHROPIC_API_KEY` env var (CLI). GitHub auth relies entirely on whichever `gh auth` account is active — there's no token resolution, no `GH_TOKEN` injection, and no account abstraction. This caused a real failure when running `claude-chain` locally: it couldn't access the demo repo because the wrong `gh` account was active.

PRRadar has a mature credential system with:
- **3-tier resolution**: env vars → `.env` file → macOS Keychain
- **Account-scoped credentials**: each repo config links to a named credential account
- **KeychainSDK**: platform-abstracted keychain access (`SecurityCLIKeychainStore` for macOS, `EnvironmentKeychainStore` for non-macOS)
- **CLI commands**: `credentials add/list/show/remove`
- **SwiftUI management**: `CredentialManagementView` with account list, detail, and edit sheet
- **`GH_TOKEN` injection**: resolved token injected into subprocess environments

This spec ports PRRadar's entire credential/config system to AIDevTools, adapted to our 4-layer architecture.

## Source files (PRRadar)

All source files live in `/Users/bill/Developer/personal/PRRadar/PRRadarLibrary/`:

| PRRadar File | Layer | What It Does |
|---|---|---|
| `sdks/KeychainSDK/KeychainStoring.swift` | SDK | Protocol + error enum |
| `sdks/KeychainSDK/SecurityCLIKeychainStore.swift` | SDK | macOS keychain via `security` CLI |
| `sdks/KeychainSDK/EnvironmentKeychainStore.swift` | SDK | Env var fallback (non-macOS) |
| `services/PRRadarConfigService/SettingsService.swift` | Service | Keychain CRUD, JSON settings persistence |
| `services/PRRadarConfigService/CredentialResolver.swift` | Service | 3-tier resolution (env → .env → keychain) |
| `services/PRRadarConfigService/GitHubAuth.swift` | Service | Enum: `.token(String)` / `.app(...)` |
| `services/PRRadarConfigService/AppSettings.swift` | Service | Root settings model (Codable) |
| `features/PRReviewFeature/Models/CredentialStatus.swift` | Feature | View model for credential UI display |
| `features/PRReviewFeature/UseCases/SaveCredentialsUseCase.swift` | Feature | Store credentials for an account |
| `features/PRReviewFeature/UseCases/ListCredentialAccountsUseCase.swift` | Feature | List stored account names |
| `features/PRReviewFeature/UseCases/RemoveCredentialsUseCase.swift` | Feature | Delete credentials for an account |
| `features/PRReviewFeature/UseCases/LoadCredentialStatusUseCase.swift` | Feature | Get credential status for one account |
| `features/PRReviewFeature/UseCases/CredentialStatusLoader.swift` | Feature | Internal utility to build statuses |
| `apps/MacCLI/Commands/CredentialsCommand.swift` | App (CLI) | `credentials add/list/show/remove` |
| `apps/MacApp/UI/CredentialManagementView.swift` | App (Mac) | SwiftUI credential management UI |
| `apps/MacApp/Models/SettingsModel.swift` | App (Mac) | Observable model for settings + credentials |

## Architectural mapping (PRRadar → AIDevTools)

| PRRadar | AIDevTools Target | Layer | Path |
|---|---|---|---|
| `KeychainSDK` | `KeychainSDK` (new) | SDKs | `Sources/SDKs/KeychainSDK/` |
| `PRRadarConfigService` (credential parts) | `CredentialService` (new) | Services | `Sources/Services/CredentialService/` |
| `PRReviewFeature` (credential use cases) | `CredentialFeature` (new) | Features | `Sources/Features/CredentialFeature/` |
| `CredentialsCommand` | Add to `AIDevToolsKitCLI` | Apps | `Sources/Apps/AIDevToolsKitCLI/` |
| `CredentialManagementView` | Add to `AIDevToolsKitMac` | Apps | `Sources/Apps/AIDevToolsKitMac/` |
| `SettingsModel` (credential parts) | New `CredentialModel` | Apps | `Sources/Apps/AIDevToolsKitMac/` |

**Key adaptations from PRRadar:**
- Service identifier: `com.gestrich.AIDevTools` (not `com.gestrich.PRRadar`)
- No `AppSettings`/`RepositoryConfigurationJSON` port — AIDevTools already has its own repo/settings system. We only port the **credential** parts of SettingsService
- Reuse existing `EnvironmentSDK` (already has `DotEnvironmentLoader`)
- `CredentialResolver` needs a `githubAccount` parameter — the Mac app passes the account associated with the selected repo; the CLI can accept it as an option or use a default

## Phases

## - [x] Phase 1: Port KeychainSDK to SDKs layer

**Skills used**: `swift-architecture`
**Principles applied**: Ported as stateless SDK with no app-specific logic; added alphabetically-sorted env var mappings for GitHub App auth; kept `#if os(macOS)` platform guard on `SecurityCLIKeychainStore`

**Skills to read**: `swift-architecture`

Port the 3 KeychainSDK files from PRRadar as-is (minimal changes needed):

1. Create `Sources/SDKs/KeychainSDK/` directory
2. Copy `KeychainStoring.swift` — no changes needed
3. Copy `SecurityCLIKeychainStore.swift` — no changes needed (already `#if os(macOS)` guarded)
4. Copy `EnvironmentKeychainStore.swift` — add `"github-app-id"`, `"github-app-installation-id"`, `"github-app-private-key"` mappings to `typeToEnvVar` dict (PRRadar only maps `github-token` and `anthropic-api-key`)
5. Add `KeychainSDK` target to `Package.swift`:
   - Library product (alphabetically placed)
   - Target with path `Sources/SDKs/KeychainSDK`, no dependencies
   - Test target `KeychainSDKTests` with path `Tests/SDKs/KeychainSDKTests`
6. Write tests: `SecurityCLIKeychainStore` round-trip (set/get/remove/allKeys), `EnvironmentKeychainStore` env var resolution, base64 encoding for multiline values
7. Build: `swift build --target KeychainSDK`

## - [x] Phase 2: Create CredentialService in Services layer

**Skills used**: `swift-architecture`
**Principles applied**: Ported only credential parts of SettingsService (not AppSettings/config management); renamed to CredentialSettingsService to avoid confusion; service identifier uses `com.gestrich.AIDevTools`; CredentialResolver depends on existing EnvironmentSDK for DotEnvironmentLoader; kept alphabetical ordering of static constants and credential type iterations

**Skills to read**: `swift-architecture`

Port the credential-related parts of PRRadar's `PRRadarConfigService`. This does **not** include `AppSettings`, `RepositoryConfigurationJSON`, or configuration management — AIDevTools has its own. We port only credential storage and resolution.

1. Create `Sources/Services/CredentialService/` directory
2. Port `GitHubAuth.swift` — enum with `.token(String)` and `.app(appId:installationId:privateKeyPEM:)` cases. No changes needed.
3. Port `SettingsService.swift` → rename to `CredentialSettingsService.swift` to avoid confusion with AIDevTools' existing settings. Changes from PRRadar:
   - Class name: `CredentialSettingsService`
   - Service identifier: `com.gestrich.AIDevTools`
   - App Support path: `AIDevTools` (not `PRRadar`)
   - Remove all configuration management methods (`addConfiguration`, `removeConfiguration`, `setDefault`, `load`/`save` for AppSettings). Keep only:
     - `saveGitHubAuth` / `loadGitHubAuth`
     - `saveAnthropicKey` / `loadAnthropicKey`
     - `removeCredentials`
     - `listCredentialAccounts`
     - `loadCredential` (internal helper)
   - Keep the `platformKeychain()` factory and both init paths
4. Port `CredentialResolver.swift` — changes from PRRadar:
   - Import `EnvironmentSDK` (AIDevTools' existing target, not a new one)
   - Constructor takes `CredentialSettingsService` instead of `SettingsService`
   - Same 3-tier resolution: process env → `.env` → keychain
5. Add `CredentialService` target to `Package.swift`:
   - Library product (alphabetically placed)
   - Target with path `Sources/Services/CredentialService`, dependencies: `KeychainSDK`, `EnvironmentSDK`
   - Test target `CredentialServiceTests` with path `Tests/Services/CredentialServiceTests`
6. Write tests: `CredentialResolver` resolution order (env wins over keychain, keychain used when env missing), `CredentialSettingsService` CRUD with injected mock keychain
7. Build: `swift build --target CredentialService`

## - [x] Phase 3: Create CredentialFeature in Features layer

**Skills used**: `swift-architecture`
**Principles applied**: Use cases are Sendable structs in Features layer; each use case wraps a single user action delegating to CredentialSettingsService; CredentialStatusLoader kept internal as an implementation detail; GitHubAuthStatus enum cases sorted alphabetically

**Skills to read**: `swift-architecture`

Port the credential use cases from PRRadar's `PRReviewFeature`.

1. Create `Sources/Features/CredentialFeature/` directory with `Models/` and `UseCases/` subdirectories
2. Port `CredentialStatus.swift` to `Models/` — no changes (just update import from `PRRadarConfigService` types to nothing needed — it's self-contained)
3. Port use cases to `UseCases/`:
   - `SaveCredentialsUseCase.swift` — change `SettingsService` → `CredentialSettingsService`, import `CredentialService`
   - `ListCredentialAccountsUseCase.swift` — same change
   - `RemoveCredentialsUseCase.swift` — same change
   - `LoadCredentialStatusUseCase.swift` — same change
   - `CredentialStatusLoader.swift` — same change (keep internal access)
4. Add `CredentialFeature` target to `Package.swift`:
   - Library product (alphabetically placed)
   - Target with path `Sources/Features/CredentialFeature`, dependency: `CredentialService`
   - Test target `CredentialFeatureTests` with path `Tests/Features/CredentialFeatureTests`
5. Write tests: `SaveCredentialsUseCase` stores and returns updated statuses, `RemoveCredentialsUseCase` clears account
6. Build: `swift build --target CredentialFeature`

## - [x] Phase 4: Add credential CLI commands to AIDevToolsKitCLI

**Skills used**: `swift-architecture`
**Principles applied**: Followed existing flat file convention for CLI commands (no subdirectory); registered subcommand alphabetically in EntryPoint; updated help text to reference `ai-dev-tools-kit` instead of PRRadar's `config`; Apps layer uses Feature and Service layer use cases directly per architecture pattern

**Skills to read**: `swift-architecture`

Port PRRadar's `CredentialsCommand` into the existing `AIDevToolsKitCLI` target.

1. Create `Sources/Apps/AIDevToolsKitCLI/Commands/CredentialsCommand.swift`
2. Port from PRRadar's `CredentialsCommand.swift` with these changes:
   - Import `CredentialService` and `CredentialFeature` (instead of `PRRadarConfigService` and `PRReviewFeature`)
   - Use `CredentialSettingsService()` instead of `SettingsService()`
   - Keep all 4 subcommands: `add`, `list`, `remove`, `show`
   - Keep GitHub App auth support (`--app-id`, `--installation-id`, `--private-key-path`)
3. Register `CredentialsCommand` in the CLI's top-level command configuration (alphabetically placed)
4. Add `CredentialFeature` and `CredentialService` to `AIDevToolsKitCLI` target dependencies in `Package.swift`
5. Build: `swift build --target AIDevToolsKitCLI`
6. Test manually: `ai-dev-tools-kit credentials list`, `ai-dev-tools-kit credentials add testaccount --github-token fake-token`, `ai-dev-tools-kit credentials show testaccount`, `ai-dev-tools-kit credentials remove testaccount`

## - [x] Phase 5: Add CredentialModel and CredentialManagementView to Mac app

**Skills used**: `swift-swiftui`
**Principles applied**: Model-View pattern with `@Observable` model injected via Environment; CredentialModel is a root-level `@State` in both entry views; removed `@AppStorage("anthropicAPIKey")` from GeneralSettingsView in favor of keychain-backed credentials; added Credentials tab to SettingsView; use cases injected via convenience init with alphabetically sorted properties

**Skills to read**: `swift-swiftui`

Port the Mac app credential management UI.

1. Create `Sources/Apps/AIDevToolsKitMac/Models/CredentialModel.swift`:
   - `@MainActor @Observable final class CredentialModel`
   - Port the credential-related parts from PRRadar's `SettingsModel`: `credentialAccounts` property, `saveCredentials()`, `removeCredentials()`, `credentialStatus()` methods
   - Inject use cases: `ListCredentialAccountsUseCase`, `SaveCredentialsUseCase`, `RemoveCredentialsUseCase`, `LoadCredentialStatusUseCase`
   - Convenience init creates `CredentialSettingsService()` and wires use cases
2. Create `Sources/Apps/AIDevToolsKitMac/Views/CredentialManagementView.swift`:
   - Port from PRRadar's `CredentialManagementView.swift`
   - Change `@Environment(SettingsModel.self)` → `@Environment(CredentialModel.self)`
   - Change imports from `PRRadarConfigService`/`PRReviewFeature` → `CredentialService`/`CredentialFeature`
   - Keep all supporting types: `GitHubAuthMode`, `EditableCredential`, `AccountDetailView`, `CredentialEditSheet`
3. Update `GeneralSettingsView.swift`:
   - Remove the `@AppStorage("anthropicAPIKey")` field and the Anthropic API section
   - Add `CredentialManagementView()` as a new settings tab or section (replacing the old API key field)
4. Wire `CredentialModel` into the app entry point:
   - Add `@State private var credentialModel: CredentialModel` to the entry view
   - Add `.environment(credentialModel)` to the view hierarchy
5. Add `CredentialFeature` and `CredentialService` to `AIDevToolsKitMac` target dependencies in `Package.swift` (if not already added in Phase 4)
6. Build: `swift build --target AIDevToolsKitMac`

## - [x] Phase 6: Wire CredentialResolver into ProviderModel and CLIRegistryFactory

**Skills used**: `swift-architecture`
**Principles applied**: Replaced ad-hoc UserDefaults credential storage with CredentialResolver's 3-tier resolution (env → .env → keychain); used NotificationCenter to bridge credential changes from settings window to main window's ProviderModel; kept closure-based API in ProviderModel for testability

**Skills to read**: `swift-architecture`

Replace the current ad-hoc credential resolution with `CredentialResolver`.

### Mac app (ProviderModel)
1. Update `ProviderModel` to accept a credential source that uses `CredentialResolver`:
   - Change the `anthropicAPIKeySource` closure to resolve via `CredentialSettingsService` + `CredentialResolver`
   - The Mac app's `CompositionRoot` should create a `CredentialSettingsService` and pass a closure that calls `CredentialResolver.getAnthropicKey()` for the active account
   - This means the Mac app reads API keys from the keychain (stored via the new `CredentialManagementView`) instead of `UserDefaults`
2. Remove the `UserDefaults` storage for `anthropicAPIKey` — credentials now live in the keychain

### CLI (CLIRegistryFactory)
1. Update `CLIRegistryFactory.makeAnthropicClientIfAvailable()`:
   - Create a `CredentialResolver` with a default account (or account from CLI option)
   - Call `resolver.getAnthropicKey()` — this checks env var first, then `.env`, then keychain
   - This is mostly a behavior-preserving change (env var still works) but adds `.env` and keychain as fallbacks
2. Add `CredentialService` to `AIDevToolsKitCLI` dependencies if not already present

### Build and test
- `swift build`
- Verify Mac app still resolves Anthropic key (now from keychain after storing via Credential Management)
- Verify CLI still resolves from `ANTHROPIC_API_KEY` env var

## - [x] Phase 7: Wire CredentialResolver into ClaudeChain for GH_TOKEN injection

**Skills used**: `swift-architecture`
**Principles applied**: Used setenv() approach in PrepareCommand/FinalizeCommand so all child gh processes inherit GH_TOKEN; CredentialResolver resolves GITHUB_TOKEN (env → .env → keychain) with GH_TOKEN env fallback for GitHub Actions compatibility; ExecuteChainUseCase accepts optional githubAccount and injects GH_TOKEN into subprocess environment; kept alphabetical import ordering

**Skills to read**: `swift-architecture`

This is the phase that fixes the original `gh auth switch` problem.

### ExecuteChainUseCase
1. Update `ExecuteChainUseCase.Options` to accept an optional `githubAccount: String?`
2. In `runProcess(arguments:workingDirectory:)`, inject `GH_TOKEN` into the subprocess environment when a GitHub token is resolved:
   - Create `CredentialResolver` with the github account
   - Call `resolver.getGitHubAuth()` → extract token (for `.token` case)
   - Set `process.environment` to include `GH_TOKEN=<resolved token>` alongside inherited env
   - This makes `gh` commands use the resolved token regardless of active `gh auth` account
3. Add `CredentialService` to `ClaudeChainFeature` target dependencies

### FinalizeCommand
1. Update to use `CredentialResolver` for `GH_TOKEN` instead of raw `env["GH_TOKEN"]`
2. Fall back to env var if resolver returns nil (for GitHub Actions compatibility where `GH_TOKEN` is already set)

### PrepareCommand
1. The `gh` calls in `PrepareCommand` (via `PRService`, `TaskService`, `AssigneeService`) go through `GitHubOperations.runGhCommand()`. Update `GitHubOperations` to optionally accept a `GH_TOKEN` that gets injected into the `gh` subprocess environment.
2. Alternatively, set `GH_TOKEN` in the process environment early in `PrepareCommand.run()` via `setenv()` so all child `gh` processes inherit it.

### Build and test
- `swift build --target ClaudeChainMain`
- Test: store a GitHub token via `ai-dev-tools-kit credentials add gestrich --github-token <token>`, then run `claude-chain prepare` without `gh auth switch` — it should use the keychain token

## - [x] Phase 8: Validation

**Skills used**: `swift-testing`
**Principles applied**: Verified all 6 targets build; all 41 credential tests pass (KeychainSDKTests: 18, CredentialServiceTests: 14, CredentialFeatureTests: 9); full build succeeds; no stale UserDefaults/AppStorage anthropicAPIKey usage; GH_TOKEN env usage is proper fallback pattern (CredentialResolver first, env fallback for GitHub Actions)

**Skills to read**: `swift-testing`

1. Build all new targets:
   - `swift build --target KeychainSDK`
   - `swift build --target CredentialService`
   - `swift build --target CredentialFeature`
   - `swift build --target AIDevToolsKitCLI`
   - `swift build --target AIDevToolsKitMac`
   - `swift build --target ClaudeChainMain`
2. Run all new test targets:
   - `swift test --filter KeychainSDKTests`
   - `swift test --filter CredentialServiceTests`
   - `swift test --filter CredentialFeatureTests`
3. Full build: `swift build`
4. Full tests: `swift test`
5. Manual verification:
   - CLI: `ai-dev-tools-kit credentials add gestrich --github-token <token> --anthropic-key <key>`
   - CLI: `ai-dev-tools-kit credentials list` → shows `gestrich`
   - CLI: `ai-dev-tools-kit credentials show gestrich` → shows masked values
   - Mac app: open Settings → Credentials tab shows accounts, can add/edit/remove
   - End-to-end: run `claude-chain prepare` against `claude-chain-demo` using keychain credentials (no `gh auth switch` needed)
6. Verify no stale `UserDefaults` usage for `anthropicAPIKey` remains
7. Verify no stale raw `env["GH_TOKEN"]` usage remains in ClaudeChain (except as fallback)
