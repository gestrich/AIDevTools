> **2026-03-29 Obsolescence Evaluation:** Completed. All phases marked [x] complete. Repository-to-credential-account linking has been implemented, including UI updates, CLI support, GH_TOKEN injection for plan execution, and removal of deprecated githubUser field.

## Relevant Skills

| Skill | Description |
|-------|-------------|
| `swift-architecture` | 4-layer architecture (Apps, Features, Services, SDKs) with placement guidance |
| `swift-swiftui` | Model-View patterns — `@Observable` models, enum-based state, dependency injection |

## Background

The credential system (spec `2026-03-28-h`) ported PRRadar's 3-tier credential resolution to AIDevTools — credentials can be stored per named account (e.g. "gestrich", "work") and resolved from env → `.env` → keychain. However, the spec explicitly excluded porting PRRadar's **repo-to-credential-account mapping**.

In PRRadar, each `RepositoryConfigurationJSON` has a `githubAccount: String` field that links it to a credential account. The edit UI shows a Picker dropdown populated from credential accounts. At runtime, `CredentialResolver` uses that account name to fetch the right token.

In AIDevTools, `RepositoryInfo` has a `githubUser: String?` field that is a **plain text field** with no connection to the credential system. It's only used to generate `gh auth switch -u <username>` instructions that get passed to Claude — a workaround that the credential system should replace.

This spec connects repositories to credential accounts so that:
- Each repo can be linked to a named credential account
- The Mac app's repo edit UI shows a credential account Picker (not a freeform text field)
- `ExecutePlanUseCase` injects `GH_TOKEN` into the subprocess environment instead of telling Claude to run `gh auth switch`
- `GeneratePlanUseCase` includes the resolved credential context instead of auth switch instructions

## Files affected

| File | Layer | Change |
|---|---|---|
| `Sources/SDKs/RepositorySDK/RepositoryInfo.swift` | SDK | Add `credentialAccount` field |
| `Sources/Apps/AIDevToolsKitMac/Views/ConfigurationEditSheet.swift` | App (Mac) | Replace GitHub User TextField with credential account Picker |
| `Sources/Apps/AIDevToolsKitMac/Views/RepositoriesSettingsView.swift` | App (Mac) | Display credential account in detail view |
| `Sources/Apps/AIDevToolsKitCLI/ReposCommand.swift` | App (CLI) | Add `--credential-account` option, deprecate `--github-user` |
| `Sources/Features/MarkdownPlannerFeature/usecases/ExecutePlanUseCase.swift` | Feature | Inject `GH_TOKEN` via `CredentialResolver` instead of `gh auth switch` instructions |
| `Sources/Features/MarkdownPlannerFeature/usecases/GeneratePlanUseCase.swift` | Feature | Replace `gh auth switch` context with credential account context |
| `Tests/SDKs/RepositorySDKTests/RepositoryInfoTests.swift` | Test | Update for new field |

## Phases

## - [x] Phase 1: Add `credentialAccount` to RepositoryInfo

**Skills used**: `swift-architecture`
**Principles applied**: Added field alphabetically between `description` and `githubUser` per SDK layer conventions. Kept `githubUser` intact for non-breaking migration. All optional params default to `nil` so no callers needed updating.

**Skills to read**: `swift-architecture`

Add a `credentialAccount: String?` field to `RepositoryInfo` alongside the existing `githubUser` field. Keep `githubUser` for now (removed in Phase 5) so the migration is non-breaking.

1. Edit `Sources/SDKs/RepositorySDK/RepositoryInfo.swift`:
   - Add `public var credentialAccount: String?` (alphabetically between `description` and `githubUser`)
   - Add to `init()` parameter list (alphabetically placed)
   - Add to `with(id:)` copy method
2. Update `Tests/SDKs/RepositorySDKTests/RepositoryInfoTests.swift` for the new field
3. Fix all compilation errors from the new init parameter — callers that construct `RepositoryInfo` directly will need updating. Find them with: `swift build 2>&1 | grep error`
4. Build: `swift build`

## - [x] Phase 2: Update Mac app edit UI with credential account Picker

**Skills used**: `swift-swiftui`
**Principles applied**: Used `@Environment(CredentialModel.self)` for dependency injection per MV pattern. Kept `credentialAccountText` as `@State` (view-owned form state). Preserved `githubUser` pass-through for non-breaking migration per Phase 1 convention.

**Skills to read**: `swift-swiftui`

Replace the "GitHub User" TextField in `ConfigurationEditSheet` with a "Credential Account" Picker populated from `CredentialModel`.

1. Edit `ConfigurationEditSheet.swift`:
   - Add `@Environment(CredentialModel.self) private var credentialModel`
   - Replace `@State private var githubUserText: String` with `@State private var credentialAccountText: String` (initialized from `config.credentialAccount ?? ""`)
   - Replace the "GitHub User" `LabeledContent` block (lines 79-82) with a "Credential Account" Picker:
     ```swift
     LabeledContent("Credential Account") {
         Picker("", selection: $credentialAccountText) {
             Text("None").tag("")
             ForEach(credentialModel.credentialAccounts, id: \.account) { status in
                 Text(status.account).tag(status.account)
             }
         }
     }
     ```
   - In `saveRepository()`, pass `credentialAccount: credentialAccountText.isEmpty ? nil : credentialAccountText` to the `RepositoryInfo` constructor
   - Keep passing `githubUser` as-is for now (it will be removed in Phase 5)
2. Edit `RepositoriesSettingsView.swift`:
   - Replace `detailRow("GitHub User", value: config.githubUser)` with `detailRow("Credential Account", value: config.credentialAccount)`
3. Build: `swift build --target AIDevToolsKitMac`

## - [x] Phase 3: Update CLI `repos update` command

**Skills used**: `swift-architecture`
**Principles applied**: Added `--credential-account` option alphabetically among existing options. Passed `credentialAccount` through both `RepositoryInfo` constructor call sites in the update path to preserve the field during path/name changes.

**Skills to read**: `swift-architecture`

Add `--credential-account` option to the CLI repos command.

1. Edit `Sources/Apps/AIDevToolsKitCLI/ReposCommand.swift`:
   - Add `@Option(help: "Credential account name for GitHub auth") var credentialAccount: String?`
   - In the update logic, add: `if let credentialAccount { repo.credentialAccount = credentialAccount }`
2. Build: `swift build --target AIDevToolsKitCLI`

## - [x] Phase 4: Wire CredentialResolver into ExecutePlanUseCase and GeneratePlanUseCase

**Skills used**: `swift-architecture`
**Principles applied**: Followed existing `ExecuteChainUseCase` pattern for `CredentialResolver` usage. Injected `GH_TOKEN` via `AIClientOptions.environment` (the AI subprocess environment) rather than `setenv()` to avoid global state. Replaced `gh auth switch` instructions in both use cases — `ExecutePlanUseCase` now injects the token directly, `GeneratePlanUseCase` now tells the plan that auth is handled automatically.

**Skills to read**: `swift-architecture`

This is the key phase — replace `gh auth switch` instructions with actual `GH_TOKEN` injection.

### ExecutePlanUseCase
1. Edit `Sources/Features/MarkdownPlannerFeature/usecases/ExecutePlanUseCase.swift`:
   - Add `import CredentialService`
   - In `executePhase(...)`, resolve `GH_TOKEN` from the repo's credential account:
     ```swift
     if let credentialAccount = repository?.credentialAccount {
         let resolver = CredentialResolver(
             settingsService: CredentialSettingsService(),
             githubAccount: credentialAccount
         )
         if case .token(let token) = resolver.getGitHubAuth() {
             // inject GH_TOKEN into the subprocess environment
         }
     }
     ```
   - Remove the `gh auth switch` instruction generation (lines 319-321). Keep the `gh pr create --draft` instruction.
   - The subprocess environment injection approach depends on how `AIClientOptions` passes environment to Claude. If it uses `Process`, inject `GH_TOKEN` into the process environment. If it spawns a `claude` CLI subprocess, set `GH_TOKEN` via `setenv()` before the call (same pattern as Phase 7 of the credential spec).

### GeneratePlanUseCase
1. Edit `Sources/Features/MarkdownPlannerFeature/usecases/GeneratePlanUseCase.swift`:
   - Remove the `gh auth switch` context line (lines 172-174)
   - Optionally replace with: `repoContextLines.append("Credential account: \(credentialAccount) (GH_TOKEN injected automatically)")` so the plan knows auth is handled

### Package.swift
1. Add `CredentialService` to `MarkdownPlannerFeature` target dependencies

### Build and test
- `swift build`
- Verify: configure a repo with a credential account, generate a plan — it should not contain `gh auth switch` instructions
- Verify: execute a plan phase — `GH_TOKEN` should be injected into the environment

## - [x] Phase 5: Remove deprecated `githubUser` field

**Skills used**: `swift-architecture`
**Principles applied**: Removed `githubUser` from all layers (SDK, App, CLI, Tests) following the downward dependency flow. Existing `repositories.json` files with `githubUser` will silently ignore the field since Codable skips unknown keys.

**Skills to read**: `swift-architecture`

Now that `credentialAccount` is wired through everywhere, remove the old `githubUser` field.

1. Edit `RepositoryInfo.swift`: remove `githubUser` property, remove from `init()`, remove from `with(id:)`
2. Edit `ConfigurationEditSheet.swift`: remove `githubUserText` state and any remaining references
3. Edit `ReposCommand.swift`: remove `--github-user` option
4. Fix all compilation errors: `swift build 2>&1 | grep error`
5. Run tests: `swift test`

**Migration note**: Existing `repositories.json` files with `githubUser` set will silently ignore the field (Codable skips unknown keys). Users will need to re-set the credential account for repos that had `githubUser` configured. This is acceptable since the field was just informational text before.

## - [x] Phase 6: Validation

**Skills used**: `swift-testing`
**Principles applied**: Verified build succeeds, all RepositorySDK tests pass (11/11), no remaining `githubUser` references in source code, no `gh auth switch` instructions in source code. Pre-existing SkillScannerTests failures are unrelated to this work.

**Skills to read**: `swift-testing`

1. Build all targets: `swift build`
2. Run all tests: `swift test`
3. Manual verification:
   - Mac app: open Settings → Repositories → edit a repo → "Credential Account" shows a Picker with accounts from the Credentials tab
   - Mac app: select a credential account, save, verify it persists
   - Mac app: detail view shows "Credential Account" instead of "GitHub User"
   - CLI: `ai-dev-tools-kit repos update AIDevTools --credential-account gestrich`
   - CLI: `ai-dev-tools-kit repos show AIDevTools` → shows credential account
   - Generate a plan for a repo with a credential account — no `gh auth switch` in the output
   - Execute a plan phase — `GH_TOKEN` should be injected (verify with a `gh` command that requires auth)
4. Verify no remaining references to `githubUser` in source code (only in git history/docs)
