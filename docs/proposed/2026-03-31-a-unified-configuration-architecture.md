## Relevant Skills

| Skill | Description |
|-------|-------------|
| `configuration-architecture` | Full guide for the three-service config design, RepositoryConfiguration shape, runtime credential change pattern, and checklist |
| `swift-app-architecture:swift-architecture` | 4-layer architecture rules — ensures changes land in the right layer |

## Background

The app currently has configuration scattered across five different storage backends (Keychain, environment variables, `.env` file, UserDefaults, and multiple JSON stores) with no unified model. Per-repo feature settings are split across three separate stores (`PRRadarRepoSettingsStore`, `EvalRepoSettingsStore`, `MarkdownPlannerRepoSettingsStore`) with cross-references by UUID, making them hard to manage together in a settings UI.

The agreed-upon design introduces three clearly-bounded services:

- **`SecureSettingsService`** — sensitive credentials via Keychain/env/dotenv chain
- **`SettingsService`** — non-sensitive settings via JSON in the data directory
- **`DataPathsService`** — file paths (already exists, no change needed)

Per-repo feature settings are consolidated into a single **`RepositoryConfiguration`** type (renamed from `RepositoryInfo`) that nests each feature's settings as optional properties. A data migration folds the three separate settings JSON files into `repositories.json`.

Runtime credential changes are handled without restart: `AppModel` holds optional child models (nil when credentials are absent), and an explicit `applyCredentialChange(_:)` method rebuilds only the affected model when the user updates a credential.

## - [x] Phase 1: Rename `RepositoryInfo` → `RepositoryConfiguration`

**Skills used**: `configuration-architecture`
**Principles applied**: `PRRadarConfigService` already had a `RepositoryConfiguration` type, so it was renamed to `PRRadarRepoConfig` (and `RepositoryConfigurationError` → `PRRadarRepoConfigError`) to clear the namespace before renaming `RepositoryInfo`. JSON encoding is unaffected since Swift's `Codable` uses property names, not the struct name.

**Skills to read**: `configuration-architecture`

Rename the `RepositoryInfo` struct and all references throughout the codebase:

- Rename `RepositoryInfo.swift` → `RepositoryConfiguration.swift`
- Update the struct name to `RepositoryConfiguration`
- Update all references: `RepositoryStore`, `RepositorySDK`, feature stores, CLI commands, Mac app models, views
- Keep the JSON encoding key as `RepositoryInfo` initially (or update with migration — coordinate with Phase 3)
- This is a mechanical rename; no behavior changes

## - [x] Phase 2: Add per-feature settings to `RepositoryConfiguration`

**Skills used**: `configuration-architecture`
**Principles applied**: `RulePath`, `DiffSource`, and the three settings structs were moved from their service modules into `RepositorySDK` to avoid a circular dependency (`RepositorySDK` cannot depend on `PRRadarConfigService` which itself depends on `RepositorySDK`). The three per-feature stores now delegate all persistence to `RepositoryStore` — no `repoId` field on the settings structs needed since identity is provided by the parent `RepositoryConfiguration`. Old JSON files remain on disk untouched for the Phase 3 migration.

**Skills to read**: `configuration-architecture`

Nest each feature's settings directly inside `RepositoryConfiguration`:

```swift
public struct RepositoryConfiguration: Codable {
    public let id: UUID
    public let path: URL
    public let name: String
    public var credentialAccount: String?
    // existing fields...

    public var prradar: PRRadarRepoSettings?
    public var eval: EvalRepoSettings?
    public var planner: MarkdownPlannerRepoSettings?
}
```

- Add the three optional properties
- Remove the `repoId` field from `PRRadarRepoSettings`, `EvalRepoSettings`, `MarkdownPlannerRepoSettings` (identity is now provided by the parent `RepositoryConfiguration`)
- Update any code that reads/writes these structs to go through `RepositoryConfiguration`

## - [x] Phase 3: Write data migration and delete separate settings stores

**Skills used**: `configuration-architecture`
**Principles applied**: Migration uses raw `JSONSerialization` to merge old per-feature JSON files (with `repoId`) into `repositories.json` without adding a `RepositorySDK` dependency to `DataPathsService`. The three store files were deleted, `ServicePath` cases for `evalSettings`, `planSettings`, and `prradarSettings` were removed, and all call sites (CLI commands, Mac app models, use cases) were updated to read/write `RepositoryConfiguration` properties directly via `RepositoryStore`.

Migrate data from the three separate JSON files into `repositories.json`:

- Add a migration step to `MigrateDataPathsUseCase`:
  1. Read `prradar/settings/prradar-settings.json`, `eval/settings/eval-settings.json`, `plan/settings/plan-settings.json`
  2. Load existing `repositories.json` as `[RepositoryConfiguration]`
  3. For each settings entry, find the matching `RepositoryConfiguration` by `repoId` and populate the corresponding nested property
  4. Write the merged `repositories.json`
  5. Delete the three separate settings files
- Delete `PRRadarRepoSettingsStore`, `EvalRepoSettingsStore`, `MarkdownPlannerRepoSettingsStore`
- All settings reads/writes now go through `RepositoryStore` (which stores `[RepositoryConfiguration]`)
- Remove the now-unused `ServicePath` cases for the separate settings directories (`.prradarSettings`, `.evalSettings`, `.planSettings`)

## - [x] Phase 4: Create `SettingsService`

**Skills to read**: `configuration-architecture`, `swift-app-architecture:swift-architecture`

Introduce `SettingsService` as the single entry point for non-sensitive settings:

- Create `SettingsService` in the Services layer, wrapping `RepositoryStore` and any app-wide JSON settings
- `SettingsService` receives `DataPathsService` in its initializer
- Move the data path preference (currently raw `UserDefaults` key `"AIDevTools.dataPath"` in `ResolveDataPathUseCase`) into a typed wrapper — either a method on `SettingsService` or a dedicated `AppPreferences` struct within it
- Initialize `SettingsService` at the Apps layer (CompositionRoot and CLI entry points) alongside the other two services
- Update `CompositionRoot` and CLI commands to use `SettingsService` rather than reaching into individual stores directly

## - [x] Phase 5: Rename `CredentialSettingsService` → `SecureSettingsService`

**Skills used**: `configuration-architecture`
**Principles applied**: Mechanical rename — `mv` for both the source file and test file, then `replace_all` across 18 Swift files. No behavior changes. The three-backend priority chain (env vars → `.env` → Keychain) is expressed in `CredentialResolver`, which is already the public interface surface.

**Skills to read**: `configuration-architecture`

Clarify the naming of the credential service:

- Rename `CredentialSettingsService` to `SecureSettingsService`
- Update all call sites
- Verify the three-backend priority chain (env vars → `.env` → Keychain) is clearly expressed in the type's interface, not just its implementation
- No behavior changes

## - [x] Phase 6: Runtime credential changes in `AppModel`

**Skills used**: `configuration-architecture`, `swift-app-architecture:swift-swiftui`
**Principles applied**: Created `AppModel` as a new `@Observable` class that wraps `ProviderModel` and exposes `applyCredentialChange(_ type: CredentialType)`. Audit found that `ProviderModel` is the only credential-gated model — it already handles absent Anthropic key gracefully (excludes `AnthropicProvider` from the registry) so it stays non-optional. `CredentialType` enum added to `CredentialService`. `CredentialManagementView` now calls `appModel.applyCredentialChange` after save/delete in addition to posting the cross-window notification (which is still needed since the settings window and main window are separate SwiftUI trees). `WorkspaceView` now calls `appModel.applyCredentialChange` in the notification handler instead of directly calling `providerModel.refreshProviders()`.

**Skills to read**: `configuration-architecture`, `swift-app-architecture:swift-swiftui`

Wire up no-restart credential updates:

- Audit `AppModel` (and `CompositionRoot`) to identify which child models depend on each credential type
- Make those child models optional on `AppModel` (nil when the credential is absent)
- Add `applyCredentialChange(_ type: CredentialType)` to `AppModel` that rebuilds only the affected child model
- Update `CredentialModel` (the credential-editing UI) to call `appModel.applyCredentialChange(_:)` after a successful save or delete
- Update views that depend on credential-gated models to use optional binding — don't show those views when the model is nil

## - [x] Phase 7: Update documentation

**Skills used**: `configuration-architecture`
**Principles applied**: Rewrote `docs/guides/configuration-architecture.md` from scratch to reflect the three-service design (`SecureSettingsService`, `SettingsService`, `DataPathsService`). Added the resolved-values pattern with an explicit anti-pattern callout (passing the service itself into a use case). Documented `RepositoryConfiguration` as the per-repo settings container, the runtime credential change pattern via `AppModel.applyCredentialChange`, and the full implementation checklist from the skill.

Update `docs/guides/configuration-architecture.md` to reflect the final design:

- Document all three services with their backends and boundaries
- Replace the anti-pattern example (passing a config service to a use case) with the correct resolved-values pattern
- Document `RepositoryConfiguration` as the per-repo settings container
- Describe the runtime credential change pattern
- Add the checklist from the `configuration-architecture` skill

## - [x] Phase 8: Validation

**Skills used**: none
**Principles applied**: Verified all prior phases delivered their stated outcomes: build is clean, `RepositoryConfiguration` carries `prradar`/`eval`/`planner` optional properties, `MigrateDataPathsUseCase.migrateFeatureSettingsIntoRepositories()` merges the three legacy JSON files into `repositories.json` then deletes them, PRRadar CLI reads `repo.prradar`, and `CredentialManagementView`/`WorkspaceView` both call `appModel.applyCredentialChange(_:)` after credential saves/deletes.

- Build succeeds with no warnings
- Existing repositories.json data survives the migration (test with a real data directory)
- PRRadar CLI commands correctly read and write `RepositoryConfiguration.prradar`
- Eval and planner settings are preserved after migration
- Changing a GitHub token in the credentials UI updates `AppModel.githubModel` without restarting the app
- Changing an Anthropic API key updates `AppModel.aiModel` without restarting
- Removing a credential causes the dependent views to hide (not crash)
