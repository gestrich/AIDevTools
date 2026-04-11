## Relevant Skills

| Skill | Description |
|-------|-------------|
| `ai-dev-tools-architecture` | 4-layer rules — shared wiring belongs in Services, @Observable stays in Apps |
| `ai-dev-tools-enforce` | Run after changes to verify no new violations introduced |

## Background

The Mac app has a proper `CompositionRoot` that assembles all dependencies in one place. The two CLI targets (`AIDevToolsKitCLI`, `ClaudeChainCLI`) have no equivalent — instead they have ad-hoc factory files (`CLIRegistryFactory`, `CLICredentialSetup`) that each command calls individually, each duplicating the same provider-building logic.

The goal is a `SharedCompositionRoot` in the Services layer that builds the services both platforms need. Each platform then has its own composition root that uses `SharedCompositionRoot` and adds platform-specific things on top.

```
SharedCompositionRoot (Services)
├── Mac CompositionRoot  →  + @Observable models, MCP config writing
└── CLI CompositionRoot  →  + nothing yet (maybe CLI-specific config later)
```

**What belongs in `SharedCompositionRoot`:**
- `DataPathsService`
- `SettingsService`
- `CredentialResolver`
- `ProviderRegistry` (ClaudeProvider + CodexProvider + AnthropicProvider if key present)
- `EvalProviderRegistry` (ClaudeProvider + CodexProvider)

**What stays platform-specific:**
- Mac: `ProviderModel` (`@Observable` wrapper around `ProviderRegistry`), `SettingsModel`, `gitClientFactory`, MCP config writing
- CLI: nothing extra yet

## Phases

## - [ ] Phase 1: Create `SharedCompositionRoot` in `ProviderRegistryService`

**Skills to read**: `ai-dev-tools-architecture` (services-layer.md)

Add `Sources/Services/ProviderRegistryService/SharedCompositionRoot.swift`:

```swift
public struct SharedCompositionRoot {
    public let credentialResolver: CredentialResolver
    public let dataPathsService: DataPathsService
    public let evalProviderRegistry: EvalProviderRegistry
    public let providerRegistry: ProviderRegistry
    public let settingsService: SettingsService

    public static func create() throws -> SharedCompositionRoot {
        let dataPathsService = try DataPathsService(rootPath: AppPreferences().dataPath() ?? AppPreferences.defaultDataPath)
        try MigrateDataPathsUseCase(dataPathsService: dataPathsService).run()
        let settingsService = try SettingsService(dataPathsService: dataPathsService)
        let secureSettings = SecureSettingsService()
        let account = (try? secureSettings.listCredentialAccounts())?.first ?? "default"
        let credentialResolver = CredentialResolver(settingsService: secureSettings, githubAccount: account)
        let sessionsDirectory = try dataPathsService.path(for: .anthropicSessions)
        let providerRegistry = Self.buildProviderRegistry(credentialResolver: credentialResolver, sessionsDirectory: sessionsDirectory)
        let evalProviderRegistry = EvalProviderRegistry(entries: [
            EvalProviderEntry(client: ClaudeProvider()),
            EvalProviderEntry(client: CodexProvider()),
        ])
        return SharedCompositionRoot(
            credentialResolver: credentialResolver,
            dataPathsService: dataPathsService,
            evalProviderRegistry: evalProviderRegistry,
            providerRegistry: providerRegistry,
            settingsService: settingsService
        )
    }

    public static func buildProviderRegistry(credentialResolver: CredentialResolver, sessionsDirectory: URL) -> ProviderRegistry {
        var providers: [any AIClient] = [ClaudeProvider(), CodexProvider()]
        if let key = credentialResolver.getAnthropicKey(), !key.isEmpty {
            providers.append(AnthropicProvider(apiClient: AnthropicAPIClient(apiKey: key), sessionsDirectory: sessionsDirectory))
        }
        return ProviderRegistry(providers: providers)
    }
}
```

Update `Package.swift` to add deps to `ProviderRegistryService`:
- `AnthropicSDK`
- `ClaudeCLISDK`
- `CodexCLISDK`
- `CredentialService`
- `DataPathsService`
- `SettingsService`
- `UseCaseSDK` (for `MigrateDataPathsUseCase`, if needed)

## - [ ] Phase 2: Update Mac `CompositionRoot` to use `SharedCompositionRoot`

**Skills to read**: (none additional)

Refactor `AIDevToolsKitMac/CompositionRoot.swift` to delegate shared setup to `SharedCompositionRoot.create()`, then layer Mac-specific things on top:

```swift
static func create() throws -> CompositionRoot {
    let shared = try SharedCompositionRoot.create()
    let settingsModel = SettingsModel()
    writeMCPConfig()
    let gitClientFactory: @Sendable (String?) -> GitClient = { ... }
    return CompositionRoot(
        dataPathsService: shared.dataPathsService,
        evalProviderRegistry: shared.evalProviderRegistry,
        gitClientFactory: gitClientFactory,
        providerModel: ProviderModel(sessionsDirectory: ..., shared: shared),
        settingsModel: settingsModel,
        settingsService: shared.settingsService
    )
}
```

`ProviderModel` can hold a reference to `shared` or accept `credentialResolver` + `sessionsDirectory` so it can rebuild the registry on credential changes (its existing refresh behavior stays intact).

## - [ ] Phase 3: Add `CLICompositionRoot` and replace CLI factory files

**Skills to read**: (none additional)

Create `AIDevToolsKitCLI/CLICompositionRoot.swift`:

```swift
struct CLICompositionRoot {
    let shared: SharedCompositionRoot

    static func create() throws -> CLICompositionRoot {
        CLICompositionRoot(shared: try SharedCompositionRoot.create())
    }
}
```

Create `ClaudeChainCLI/CLICompositionRoot.swift` (same structure — separate type in its own target).

Update commands in both targets that currently call `makeProviderRegistry()` or `makeEvalRegistry()` to instead construct `CLICompositionRoot` and read from `shared.providerRegistry` / `shared.evalProviderRegistry`.

Delete `CLIRegistryFactory.swift` and `CLICredentialSetup.swift`.

## - [ ] Phase 4: Validation

**Skills to read**: `ai-dev-tools-enforce`

- Build both Mac and CLI targets
- Grep for `AnthropicProvider(`, `ClaudeProvider(`, `CodexProvider(` — only `SharedCompositionRoot.swift` should contain them
- Run `ai-dev-tools-enforce` on all changed files
