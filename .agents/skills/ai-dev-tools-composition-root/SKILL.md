---
name: ai-dev-tools-composition-root
description: >
  Guidance for this project's composition root pattern — how SharedCompositionRoot
  centralises shared service wiring, how the Mac app and CLI targets each have their
  own root that wraps it, and how platform-specific additions (models, git client,
  credentials) are layered on top. Use this when adding new shared services, creating
  a new CLI command that needs services, modifying how providers or credentials are
  wired, reviewing code that constructs services outside a composition root, or any
  time someone asks how dependency wiring works in this project.
user-invocable: true
---

# Composition Root Pattern

## Why composition roots exist

Every service in this app must be constructed somewhere. The wrong answer is
constructing them in the command or model that happens to need them — that
scatters wiring logic, makes it easy for two callers to wire the same service
differently, and hides what the app actually depends on.

The composition root is the **single place** where services are assembled.
Callers receive what they need from the root; they never build services
themselves.

This is not a singleton. The root is created once at startup (or once per
command invocation in the CLI), held by the entry point, and injected downward.
There is no `static shared`.

---

## SharedCompositionRoot (Services layer)

`Sources/Services/ProviderRegistryService/SharedCompositionRoot.swift`

Builds everything both platforms share:

| Property | Type |
|----------|------|
| `credentialResolver` | `CredentialResolver` |
| `dataPathsService` | `DataPathsService` |
| `evalProviderRegistry` | `EvalProviderRegistry` |
| `providerRegistry` | `ProviderRegistry` |
| `settingsService` | `SettingsService` |

### Factory methods

```swift
// Default credentials (reads from keychain)
SharedCompositionRoot.create()

// Custom credentials (e.g. from CLI flags)
SharedCompositionRoot.create(credentialResolver: resolver)
```

`AnthropicProvider` is added to `providerRegistry` only when an Anthropic API
key is present — `ClaudeProvider` and `CodexProvider` are always included.

`SharedCompositionRoot` lives in the Services layer so it has no upward
dependencies. It may depend on SDKs and other Services, never on Features or
Apps.

---

## Mac CompositionRoot (Apps layer)

`Sources/Apps/AIDevToolsKitMac/CompositionRoot.swift`

Calls `SharedCompositionRoot.create()`, then adds Mac-specific things on top:

- `ProviderModel` — `@Observable` wrapper around `providerRegistry` that
  refreshes when credentials change; injected into Mac models
- `SettingsModel` — `@Observable` wrapper for the data path setting
- `gitClientFactory` — closure that wires a `GitClient` with the right token
  for a given GitHub account; passed to models that make git calls
- MCP config writing

```swift
static func create() throws -> CompositionRoot {
    let shared = try SharedCompositionRoot.create()
    // ... add Mac-specific wiring
}
```

`CompositionRoot` is created once in the app entry point and injected into
views and models via the SwiftUI environment or initialiser arguments.
Models do not call `SharedCompositionRoot.create()` themselves.

---

## CLICompositionRoot (Apps layer, per CLI target)

Each CLI target has its own:
- `Sources/Apps/AIDevToolsKitCLI/CLICompositionRoot.swift`
- `Sources/Apps/ClaudeChainCLI/CLICompositionRoot.swift`

Wraps `SharedCompositionRoot` and adds the CLI's git client:

| Property | Description |
|----------|-------------|
| `credentialResolver` | For passing to services that need GitHub auth |
| `evalProviderRegistry` | For eval commands |
| `gitClient` | Credential-wired `GitClient` |
| `providerRegistry` | For commands that need an AI provider |

### Factory methods

```swift
// Default credentials
CLICompositionRoot.create()

// Credentials from CLI flags (--github-account / --github-token)
CLICompositionRoot.create(githubAccount: githubAccount, githubToken: githubToken)

// Silent git output (e.g. batch operations like SweepCommand)
CLICompositionRoot.create(githubAccount: ..., githubToken: ..., printGitOutput: false)
```

`resolveGitHubCredentials` is called **inside** the factory — callers never
build a `CredentialResolver` themselves and pass it in.

### Usage pattern in commands

```swift
func run() async throws {
    let root = try CLICompositionRoot.create(githubAccount: githubAccount, githubToken: githubToken)
    let client = root.providerRegistry.defaultClient!
    let useCase = SomeUseCase(client: client, git: root.gitClient)
    // ...
}
```

Always assign the root to a local variable first, then read from it. Do not
chain property access off `create()` directly.

---

## Rules

**Add new shared services to `SharedCompositionRoot`**, not to the individual
platform roots. If both the Mac app and a CLI need it, it belongs in shared.

**Add platform-specific services to the platform root.** `@Observable` models
are Mac-only and must never appear in `SharedCompositionRoot`.

**Commands and models never construct their own services.** If a command is
doing `let registry = ProviderRegistry(providers: [...])` or
`let resolver = CredentialResolver(...)` inline, that's a violation — move it
into the appropriate root.

**Do not expose `SharedCompositionRoot` as a public property** on
`CLICompositionRoot` or `CompositionRoot`. Surface the individual services the
platform root wants to expose; callers should not reach through to `shared`.
