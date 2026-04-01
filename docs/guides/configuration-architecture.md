# Configuration Architecture

Three services handle all configuration. All are created at the **Apps layer** and injected
downward — never instantiated inside features, services, or SDKs.

| Service | Purpose | Backend |
|---|---|---|
| `SecureSettingsService` | Sensitive credentials (API keys, tokens) | Keychain → env vars → `.env` |
| `SettingsService` | Non-sensitive app and feature settings | JSON files via `DataPathsService` |
| `DataPathsService` | Type-safe file system paths | File system |

---

## SecureSettingsService — Credentials

Reads sensitive credentials through a priority chain:
1. Process environment variables (highest — for CI and production overrides)
2. `.env` file (local development)
3. macOS Keychain (interactive use)

```swift
let secureSettings = SecureSettingsService()
let token = try secureSettings.get(.githubToken, account: "work")
let apiKey = try secureSettings.get(.anthropicAPIKey)
```

### Credential types

| Type | Keychain key | Env var |
|---|---|---|
| `.anthropicAPIKey` | `anthropic-api-key` | `ANTHROPIC_API_KEY` |
| `.githubToken` | `github-token` | `GITHUB_TOKEN` |
| `.githubAppId` | `github-app-id` | `GITHUB_APP_ID` |
| `.githubAppInstallationId` | `github-app-installation-id` | `GITHUB_APP_INSTALLATION_ID` |
| `.githubAppPrivateKey` | `github-app-private-key` | `GITHUB_APP_PRIVATE_KEY` |

### Account scoping

Credentials can be scoped to named accounts (e.g., `"work"`, `"personal"`). Keys are
stored as `{account}/{type}` in the Keychain. Use the default account when only one
credential of each type is needed.

### Adding a new credential type

1. Add a case to `CredentialType`
2. Map it to a Keychain key and env var name
3. Load it at the Apps layer and pass the resolved value (string/token) downward

---

## SettingsService — Non-Sensitive Settings

Loads and saves feature settings as JSON in the data directory. The primary entity is
`RepositoryConfiguration` — all per-repo feature settings live here.

```swift
let settings = SettingsService(dataPathsService: dataPathsService)
let configs = try settings.loadRepositories()
let config = configs.first { .id == repoId }
```

### RepositoryConfiguration

The central settings type. A repository's identity and all per-feature settings live
together in one struct:

```swift
public struct RepositoryConfiguration: Codable {
    public let id: UUID
    public let path: URL
    public let name: String
    public var credentialAccount: String?

    // Per-feature settings — nil until the feature is configured for this repo
    public var prradar: PRRadarRepoSettings?
    public var eval: EvalRepoSettings?
    public var planner: MarkdownPlannerRepoSettings?
}
```

Each feature's settings struct is self-contained and only gains meaning when nested
inside a `RepositoryConfiguration`. Adding settings for a new feature = add one optional
property here.

All `RepositoryConfiguration` objects are stored together in `repositories.json` via
`DataPathsService`'s `.repositories` path.

### Non-repo settings

Settings that are app-wide (not per-repo) also live in `SettingsService`, stored as
their own JSON files in the data directory.

### What does NOT belong in SettingsService

- Sensitive credentials → `SecureSettingsService`
- Ephemeral UI state (selected tab, filter values, scroll position) → `@AppStorage` / `UserDefaults` directly in the view layer is fine for these

---

## DataPathsService — File Paths

Provides type-safe, auto-created directory paths via `ServicePath`. Always receives its
`rootPath` from `ResolveDataPathUseCase` at the Apps layer.

```swift
let dataPathsService = try DataPathsService(rootPath: resolvedRoot)
let outputPath = try dataPathsService.path(for: .prradarOutput("my-repo"))
```

### Root path resolution

`ResolveDataPathUseCase` determines the data root in priority order:
1. Explicit `--dataPath` CLI argument
2. UserDefaults (`org.gestrich.AIDevTools.shared`, key `AIDevTools.dataPath`)
3. Default: `~/Desktop/ai-dev-tools`

### Adding a new ServicePath case

Add to the `ServicePath` enum, keeping cases sorted alphabetically:

```swift
public enum ServicePath {
    case myNewPath       // "my-feature/data/"
    case prradarOutput(String)
    case repositories
    // ...
}
```

---

## Apps Layer: Initialization

All three services are created once at the entry point. Features and services receive
**resolved values** (a token string, a `URL`, an initialized client) — never the
services themselves.

### Mac app (CompositionRoot)

```swift
static func create() throws -> CompositionRoot {
    let dataRoot = ResolveDataPathUseCase().resolve(explicit: nil).path
    let dataPathsService = try DataPathsService(rootPath: dataRoot)
    let secureSettings = SecureSettingsService()
    let settings = SettingsService(dataPathsService: dataPathsService)

    // Resolve credentials once — pass the token, not the service
    let appModel = try AppModel(
        secureSettings: secureSettings,
        settings: settings,
        dataPathsService: dataPathsService
    )
    return CompositionRoot(appModel: appModel)
}
```

### CLI command

```swift
struct MyCommand: AsyncParsableCommand {
    @Option var dataPath: String?

    func run() async throws {
        let dataPathsService = try DataPathsService.fromCLI(dataPath: dataPath)
        let secureSettings = SecureSettingsService()
        let token = try secureSettings.get(.githubToken)
        let useCase = MyUseCase(
            githubClient: GitHubClient(token: token),
            outputPath: try dataPathsService.path(for: .myOutput)
        )
        // ...
    }
}
```

**Anti-pattern** — don't pass the service itself into a use case or service:

```swift
// Wrong: use case resolves credentials itself
let useCase = MyUseCase(secureSettings: secureSettings)
```

**Correct** — resolve at the Apps layer, pass the resolved value:

```swift
// Right: use case receives the token string, not the credential service
let token = try secureSettings.get(.githubToken)
let useCase = MyUseCase(githubClient: GitHubClient(token: token))
```

---

## Runtime Credential Changes (No Restart Required)

Services that depend on credentials are wrapped in optional child models on `AppModel`.
When a credential is absent, the model is `nil` and its UI is not shown. When the user
saves a new credential, `AppModel` rebuilds just the affected child model.

```swift
@Observable class AppModel {
    var githubModel: GitHubModel?   // nil until GitHub token is available
    var aiModel: AIModel?           // nil until Anthropic API key is available

    func applyCredentialChange(_ type: CredentialType) {
        switch type {
        case .githubToken:
            githubModel = buildGitHubModel()   // recreates, or nil if token removed
        case .anthropicAPIKey:
            aiModel = buildAIModel()
        }
    }
}
```

The credential-editing UI calls `appModel.applyCredentialChange(_:)` after saving. This
makes the cause-and-effect explicit rather than relying on observation.

**Don't show views that require a credential until the model exists.** SwiftUI's optional
binding handles this naturally — no empty states needed.

---

## Checklist: Adding configuration to a feature

- [ ] Sensitive credential? → `SecureSettingsService`, loaded at Apps layer, pass resolved value downward
- [ ] Per-repo feature settings? → Add an optional property to `RepositoryConfiguration`
- [ ] App-wide non-sensitive setting? → `SettingsService`, stored as JSON in data dir
- [ ] New data directory needed? → Add a `ServicePath` case (sorted alphabetically)
- [ ] New credential type? → Add to `CredentialType`, map Keychain key and env var
- [ ] Service depends on a credential? → Wrap it in an optional child model on `AppModel`
- [ ] Use cases / services receive resolved values, not the service objects themselves
- [ ] Missing required credential: don't show the feature, not a crash
